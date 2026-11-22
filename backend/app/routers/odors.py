from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..features import GAS_CHANNELS
from ..models import Detection, Odor, TrainingSample
from ..schemas import OdorIn, OdorOut, OdorUpdate, LEVELS
from ..security import current_user

router = APIRouter(prefix="/api/odors", tags=["Bibliothèque d'odeurs"], dependencies=[Depends(current_user)])


def _out(db: Session, odor: Odor) -> OdorOut:
    out = OdorOut.model_validate(odor)
    prints = db.scalars(select(TrainingSample.fingerprint).where(TrainingSample.odor_id == odor.id)).all()
    out.samples = len(prints)
    if prints:  # empreinte moyenne de l'odeur (pour le graphique radar)
        out.fingerprint = {ch: round(sum(p.get(ch, 0.0) for p in prints) / len(prints), 4) for ch in GAS_CHANNELS}
    out.detections, out.last_detected = db.execute(
        select(func.count(Detection.id), func.max(Detection.ts)).where(Detection.odor_id == odor.id)
    ).one()
    return out


def _odor(db: Session, odor_id: int) -> Odor:
    odor = db.get(Odor, odor_id)
    if odor is None:
        raise HTTPException(404, "Odeur inconnue")
    return odor


@router.get("", response_model=List[OdorOut])
def list_odors(db: Session = Depends(get_db)):
    return [_out(db, o) for o in db.scalars(select(Odor).order_by(Odor.is_air.desc(), Odor.name)).all()]


@router.get("/{odor_id}", response_model=OdorOut)
def get_odor(odor_id: int, db: Session = Depends(get_db)):
    return _out(db, _odor(db, odor_id))


@router.post("", response_model=OdorOut, status_code=201)
def create_odor(body: OdorIn, db: Session = Depends(get_db)):
    if db.scalars(select(Odor).where(func.lower(Odor.name) == body.name.strip().lower())).first():
        raise HTTPException(409, "Cette odeur existe déjà")
    odor = Odor(**body.model_dump())
    odor.name = odor.name.strip()
    db.add(odor)
    db.commit()
    return _out(db, odor)


@router.patch("/{odor_id}", response_model=OdorOut)
def update_odor(odor_id: int, body: OdorUpdate, db: Session = Depends(get_db)):
    odor = _odor(db, odor_id)
    data = body.model_dump(exclude_unset=True)
    if "alert_level" in data and data["alert_level"] not in LEVELS:
        raise HTTPException(422, f"alert_level doit être parmi {LEVELS}")
    for key, value in data.items():
        setattr(odor, key, value)
    db.commit()
    return _out(db, odor)


@router.delete("/{odor_id}", status_code=204)
def delete_odor(odor_id: int, db: Session = Depends(get_db)):
    odor = _odor(db, odor_id)
    if odor.is_air:
        raise HTTPException(400, "La classe « Air ambiant » est nécessaire au modèle")
    db.query(TrainingSample).filter(TrainingSample.odor_id == odor_id).delete()
    db.delete(odor)
    db.commit()
