from datetime import datetime, timedelta, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Detection, Device, Measurement
from ..schemas import DeviceOut, DeviceUpdate, MeasurementOut
from ..security import current_user

router = APIRouter(prefix="/api/devices", tags=["Appareils"], dependencies=[Depends(current_user)])


def _device(db: Session, device_id: str) -> Device:
    dev = db.get(Device, device_id)
    if dev is None:
        raise HTTPException(404, "Appareil inconnu")
    return dev


@router.get("", response_model=List[DeviceOut])
def list_devices(db: Session = Depends(get_db)):
    return [DeviceOut.build(d) for d in db.scalars(select(Device).order_by(Device.name)).all()]


@router.get("/{device_id}", response_model=DeviceOut)
def get_device(device_id: str, db: Session = Depends(get_db)):
    return DeviceOut.build(_device(db, device_id))


@router.patch("/{device_id}", response_model=DeviceOut)
def update_device(device_id: str, body: DeviceUpdate, db: Session = Depends(get_db)):
    dev = _device(db, device_id)
    data = body.model_dump(exclude_unset=True)
    move_history = data.pop("move_history", False)
    old = (dev.lat, dev.lon)
    for key, value in data.items():
        setattr(dev, key, value)

    # Correction de position : les anciennes détections faites à l'ancienne position
    # (ou sans position) suivent l'appareil vers sa vraie position.
    if move_history and dev.lat is not None and dev.lon is not None and (dev.lat, dev.lon) != old:
        same_place = (Detection.lat.is_(None) | Detection.lon.is_(None)) if None in old \
            else ((Detection.lat == old[0]) & (Detection.lon == old[1]))
        db.execute(update(Detection).where(Detection.device_id == device_id, same_place)
                   .values(lat=dev.lat, lon=dev.lon))
    if "room" in data:
        db.execute(update(Detection).where(Detection.device_id == device_id, Detection.room.is_(None))
                   .values(room=dev.room))
    db.commit()
    return DeviceOut.build(dev)


@router.delete("/{device_id}", status_code=204)
def delete_device(device_id: str, db: Session = Depends(get_db)):
    dev = _device(db, device_id)
    db.execute(delete(Measurement).where(Measurement.device_id == device_id))
    db.delete(dev)
    db.commit()


@router.get("/{device_id}/measurements", response_model=List[MeasurementOut])
def measurements(device_id: str, minutes: int = Query(10, ge=1, le=1440), limit: int = Query(600, le=5000),
                 db: Session = Depends(get_db)):
    since = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    rows = db.scalars(select(Measurement).where(Measurement.device_id == device_id, Measurement.ts >= since)
                      .order_by(Measurement.ts.desc()).limit(limit)).all()
    return list(reversed(rows))


@router.post("/{device_id}/calibrate")
async def calibrate(device_id: str, request: Request, db: Session = Depends(get_db)):
    """La prochaine fenêtre de mesures devient la nouvelle référence d'air propre."""
    _device(db, device_id)
    hub = request.app.state.hub
    hub.processor.request_calibration(device_id)
    sent = await hub.send_command(device_id, {"cmd": "calibrate"})
    return {"ok": True, "command_sent": sent, "message": "Placez le capteur à l'air propre pendant ~10 secondes."}


@router.post("/{device_id}/identify")
async def identify(device_id: str, request: Request, db: Session = Depends(get_db)):
    _device(db, device_id)
    sent = await request.app.state.hub.send_command(device_id, {"cmd": "identify"})
    return {"ok": True, "command_sent": sent}
