"""Point d'entrée de l'API : uvicorn app.main:app --reload"""
import asyncio
import contextlib
import logging
import secrets

from fastapi import FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from .config import settings
from .db import SessionLocal, init_db
from .hub import Hub
from .ml import OdorModel
from .models import Odor, User
from .processing import Processor
from .routers import auth, detections, devices, odors, training
from .security import hash_password, user_id_from_token

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s : %(message)s")
log = logging.getLogger("nez")

DEFAULT_ODORS = [
    # nom, icône, couleur, niveau d'alerte, description, air ?
    ("Air ambiant", "🌿", "#6FE3C1", "none", "Air propre de référence (indispensable au modèle).", True),
    ("Café", "☕", "#C8925A", "none", "Café fraîchement moulu ou infusé.", False),
    ("Pain brûlé", "🔥", "#FF8A5B", "warning", "Toast ou plat qui brûle : fumée et COV.", False),
    ("Poubelle", "🗑️", "#9BC53D", "info", "Déchets organiques : ammoniac et soufre.", False),
    ("Fruit trop mûr", "🍌", "#F2C14E", "info", "Fermentation : éthanol.", False),
    ("Fuite de gaz", "⚠️", "#F25C54", "danger", "Méthane (gaz naturel). Aérer et couper le gaz.", False),
    ("Produit chimique", "🧪", "#A98BFF", "warning", "Solvants, peinture, produits ménagers.", False),
]


def seed() -> None:
    with SessionLocal() as db:
        email = settings.admin_email.strip().lower()
        if db.scalars(select(User).where(User.email == email)).first() is None:
            db.add(User(email=email, password_hash=hash_password(settings.admin_password)))
            log.info("Compte administrateur créé : %s", email)
        if db.scalars(select(Odor)).first() is None:
            for name, icon, color, level, desc, is_air in DEFAULT_ODORS:
                db.add(Odor(name=name, icon=icon, color=color, alert_level=level, description=desc, is_air=is_air))
        db.commit()


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    seed()
    model = OdorModel(settings.model_path)
    hub = Hub(Processor(SessionLocal, model))
    app.state.model, app.state.hub = model, hub
    task = asyncio.create_task(hub.mqtt_loop()) if settings.mqtt_enabled else None
    log.info("Modèle %s", "chargé" if model.trained else "pas encore entraîné")
    yield
    if task:
        task.cancel()


app = FastAPI(
    title="La bibliothèque des odeurs",
    description="API du nez électronique IoT : mesures, apprentissage, reconnaissance et carte olfactive.",
    version="1.0.0",
    lifespan=lifespan,
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

for r in (auth, devices, odors, training, detections):
    app.include_router(r.router)


@app.get("/api/health", tags=["Système"])
def health(request: Request):
    return {"status": "ok", "mqtt_connected": request.app.state.hub.mqtt_connected,
            "model_trained": request.app.state.model.trained}


@app.post("/api/ingest/{device_id}", tags=["Système"])
async def ingest(device_id: str, payload: dict, request: Request, x_ingest_key: str = Header("")):
    """Alternative HTTP à MQTT (simulateur, appareils sans broker). Protégé par la clé X-Ingest-Key."""
    if not secrets.compare_digest(x_ingest_key, settings.ingest_key):
        raise HTTPException(401, "Clé d'ingestion invalide")
    await request.app.state.hub.handle_reading(device_id, payload)
    return {"ok": True}


@app.websocket("/ws")
async def websocket(ws: WebSocket, token: str = ""):
    """Flux temps réel : reading, prediction, detection, alert, training_progress, device, calibrated."""
    if user_id_from_token(token) is None:
        await ws.close(code=4401)
        return
    hub: Hub = ws.app.state.hub
    await hub.connect(ws)
    try:
        while True:
            await ws.receive_text()  # le client peut envoyer "ping"
    except WebSocketDisconnect:
        pass
    finally:
        hub.disconnect(ws)
