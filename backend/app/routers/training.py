from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from ..db import get_db
from ..ml import TrainingError
from ..models import Device, Odor, TrainingSample, TrainingSession
from ..schemas import ModelInfo, SessionIn, SessionOut
from ..security import current_user

router = APIRouter(prefix="/api", tags=["Apprentissage & modèle"], dependencies=[Depends(current_user)])


@router.post("/training/sessions", response_model=SessionOut, status_code=201)
async def start_session(body: SessionIn, request: Request, db: Session = Depends(get_db)):
    """Démarre l'enregistrement d'une odeur : chaque fenêtre de mesures devient un échantillon étiqueté."""
    device = db.get(Device, body.device_id)
    odor = db.get(Odor, body.odor_id)
    if device is None or odor is None:
        raise HTTPException(404, "Appareil ou odeur inconnu")
    if not device.baseline:
        raise HTTPException(409, "Appareil pas encore calibré : attendez ~10 s de mesures à l'air propre")
    db.execute(update(TrainingSession).where(TrainingSession.device_id == body.device_id,
                                             TrainingSession.status == "active").values(status="cancelled"))
    session = TrainingSession(device_id=body.device_id, odor_id=body.odor_id,
                              target_windows=body.windows, skip_windows=body.skip_windows)
    db.add(session)
    db.commit()
    await request.app.state.hub.send_command(body.device_id, {"cmd": "learn", "odor": odor.name,
                                                              "windows": body.windows})
    return session


@router.get("/training/sessions", response_model=List[SessionOut])
def list_sessions(status: Optional[str] = None, limit: int = 20, db: Session = Depends(get_db)):
    q = select(TrainingSession).order_by(TrainingSession.id.desc()).limit(limit)
    if status:
        q = q.where(TrainingSession.status == status)
    return db.scalars(q).all()


@router.get("/training/sessions/{session_id}", response_model=SessionOut)
def get_session(session_id: int, db: Session = Depends(get_db)):
    session = db.get(TrainingSession, session_id)
    if session is None:
        raise HTTPException(404, "Session inconnue")
    return session


@router.post("/training/sessions/{session_id}/cancel", response_model=SessionOut)
def cancel_session(session_id: int, db: Session = Depends(get_db)):
    session = get_session(session_id, db)
    if session.status == "active":
        session.status = "cancelled"
        db.commit()
    return session


@router.delete("/training/samples", status_code=204)
def delete_samples(odor_id: Optional[int] = None, db: Session = Depends(get_db)):
    q = db.query(TrainingSample)
    if odor_id is not None:
        q = q.filter(TrainingSample.odor_id == odor_id)
    q.delete()
    db.commit()


def _samples_per_odor(db: Session):
    rows = db.execute(select(TrainingSample.odor_id, func.count()).group_by(TrainingSample.odor_id)).all()
    return {int(o): int(n) for o, n in rows}


@router.get("/model", response_model=ModelInfo)
def model_info(request: Request, db: Session = Depends(get_db)):
    model = request.app.state.model
    return ModelInfo(trained=model.trained, meta=model.meta, samples_per_odor=_samples_per_odor(db))


@router.post("/model/train", response_model=ModelInfo)
def train_model(request: Request, db: Session = Depends(get_db)):
    samples = db.execute(select(TrainingSample.features, TrainingSample.odor_id)).all()
    names = {o.id: o.name for o in db.scalars(select(Odor)).all()}
    model = request.app.state.model
    try:
        model.train([s[0] for s in samples], [s[1] for s in samples], names)
    except TrainingError as exc:
        raise HTTPException(422, str(exc))
    return ModelInfo(trained=True, meta=model.meta, samples_per_odor=_samples_per_odor(db))


@router.delete("/model", status_code=204)
def reset_model(request: Request):
    request.app.state.model.reset()
