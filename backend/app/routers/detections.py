import math
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select, text, update
from sqlalchemy.orm import Session

from ..db import IS_SQLITE, get_db
from ..models import Alert, Detection, Device, Odor
from ..schemas import AlertOut, DetectionOut, DeviceOut, StatsOut
from ..security import current_user

router = APIRouter(prefix="/api", tags=["Carte, détections & alertes"], dependencies=[Depends(current_user)])


@router.get("/detections", response_model=List[DetectionOut])
def list_detections(odor_id: Optional[int] = None, device_id: Optional[str] = None,
                    hours: int = Query(24 * 7, ge=1, le=24 * 365), limit: int = Query(500, le=5000),
                    db: Session = Depends(get_db)):
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    q = select(Detection).where(Detection.ts >= since)
    if odor_id is not None:
        q = q.where(Detection.odor_id == odor_id)
    if device_id:
        q = q.where(Detection.device_id == device_id)
    return db.scalars(q.order_by(Detection.ts.desc()).limit(limit)).all()


@router.get("/detections/near", response_model=List[DetectionOut])
def detections_near(lat: float, lon: float, radius_m: float = Query(500, gt=0, le=50000),
                    limit: int = 200, db: Session = Depends(get_db)):
    """Détections dans un rayon autour d'un point (PostGIS en production)."""
    if not IS_SQLITE:
        ids = db.execute(text(
            "SELECT id FROM detections WHERE geom IS NOT NULL AND "
            "ST_DWithin(geom, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography, :r) "
            "ORDER BY ts DESC LIMIT :limit"), {"lat": lat, "lon": lon, "r": radius_m, "limit": limit}).scalars().all()
        return db.scalars(select(Detection).where(Detection.id.in_(ids)).order_by(Detection.ts.desc())).all()

    def dist(a_lat, a_lon):  # formule de haversine
        p1, p2 = math.radians(lat), math.radians(a_lat)
        dp, dl = p2 - p1, math.radians(a_lon - lon)
        h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
        return 2 * 6371000 * math.asin(math.sqrt(h))

    rows = db.scalars(select(Detection).where(Detection.lat.is_not(None)).order_by(Detection.ts.desc())).all()
    return [d for d in rows if dist(d.lat, d.lon) <= radius_m][:limit]


@router.get("/stats", response_model=StatsOut)
def stats(db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc)
    since = now - timedelta(hours=24)
    odors = {o.id: o for o in db.scalars(select(Odor)).all()}

    by_odor = [{"odor_id": oid, "label": odors[oid].name if oid in odors else "?",
                "color": odors[oid].color if oid in odors else "#888888",
                "icon": odors[oid].icon if oid in odors else "❔", "count": n}
               for oid, n in db.execute(select(Detection.odor_id, func.count()).group_by(Detection.odor_id)
                                        .order_by(func.count().desc())).all()]
    by_room = [{"room": room or "Sans pièce", "count": n}
               for room, n in db.execute(select(Detection.room, func.count()).group_by(Detection.room)
                                         .order_by(func.count().desc())).all()]

    recent = db.scalars(select(Detection.ts).where(Detection.ts >= since)).all()
    buckets = [0] * 24
    for ts in recent:
        ts = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
        idx = 23 - int((now - ts).total_seconds() // 3600)
        if 0 <= idx < 24:
            buckets[idx] += 1
    timeline = [{"hour": (now - timedelta(hours=23 - i)).strftime("%H:00"), "count": c} for i, c in enumerate(buckets)]

    devices = db.scalars(select(Device)).all()
    return StatsOut(
        detections_day=len(recent),
        detections_total=db.scalar(select(func.count(Detection.id))) or 0,
        unacknowledged_alerts=db.scalar(select(func.count(Alert.id)).where(Alert.acknowledged.is_(False))) or 0,
        devices_online=sum(DeviceOut.build(d).online for d in devices),
        devices_total=len(devices),
        by_odor=by_odor, by_room=by_room, timeline=timeline,
    )


@router.get("/alerts", response_model=List[AlertOut])
def list_alerts(unacknowledged: bool = False, limit: int = Query(100, le=1000), db: Session = Depends(get_db)):
    q = select(Alert).order_by(Alert.ts.desc()).limit(limit)
    if unacknowledged:
        q = q.where(Alert.acknowledged.is_(False))
    return db.scalars(q).all()


@router.post("/alerts/{alert_id}/ack", response_model=AlertOut)
def ack_alert(alert_id: int, db: Session = Depends(get_db)):
    alert = db.get(Alert, alert_id)
    if alert is None:
        raise HTTPException(404, "Alerte inconnue")
    alert.acknowledged = True
    db.commit()
    return alert


@router.post("/alerts/ack-all")
def ack_all(db: Session = Depends(get_db)):
    n = db.execute(update(Alert).where(Alert.acknowledged.is_(False)).values(acknowledged=True)).rowcount
    db.commit()
    return {"acknowledged": n}
