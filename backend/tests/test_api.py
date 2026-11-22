"""Tests de bout en bout : calibration → apprentissage → entraînement → reconnaissance → alerte.

Lancer depuis backend/ :  pytest -q
"""
import os
import sys
import tempfile

TMP = tempfile.mkdtemp()
os.environ.update(DATABASE_URL=f"sqlite:///{TMP}/test.db", MODEL_PATH=f"{TMP}/model.joblib",
                  MQTT_ENABLED="false", INGEST_KEY="k", DETECTION_COOLDOWN_S="0")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "simulator"))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from simulate import Nose  # noqa: E402

DEV = "nez-test"


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        token = c.post("/api/auth/login", json={"email": "admin@nez.local", "password": "admin1234"}).json()["access_token"]
        c.headers["Authorization"] = f"Bearer {token}"
        yield c


def send(c, reading):
    r = c.post(f"/api/ingest/{DEV}", json={"device": DEV, **reading}, headers={"X-Ingest-Key": "k"})
    assert r.status_code == 200, r.text


def test_auth_required():
    with TestClient(app) as c:
        assert c.get("/api/odors").status_code == 401
        assert c.post("/api/auth/login", json={"email": "admin@nez.local", "password": "faux"}).status_code == 401
        assert c.post(f"/api/ingest/{DEV}", json={}, headers={"X-Ingest-Key": "mauvaise"}).status_code == 401


def test_full_pipeline(client):
    nose = Nose(seed=1)
    for _ in range(15):
        send(client, nose.read())
    dev = client.get(f"/api/devices/{DEV}").json()
    assert dev["calibrated"] and dev["online"]
    client.patch(f"/api/devices/{DEV}", json={"room": "Cuisine", "lat": 48.85, "lon": 2.35})

    odors = {o["name"]: o for o in client.get("/api/odors").json()}
    for name in ["Air ambiant", "Café", "Fuite de gaz", "Fruit trop mûr"]:
        for _ in range(2):
            s = client.post("/api/training/sessions", json={"device_id": DEV, "odor_id": odors[name]["id"],
                                                             "windows": 5, "skip_windows": 2}).json()
            nose.expose(name)
            for _ in range(200):
                send(client, nose.read(tau=2.0))
                if client.get(f"/api/training/sessions/{s['id']}").json()["status"] == "done":
                    break
            nose.expose("Air ambiant")
            for _ in range(15):
                send(client, nose.read(tau=2.0))

    info = client.post("/api/model/train").json()
    assert info["trained"] and info["meta"]["accuracy"] > 0.8, info["meta"]

    nose.expose("Fuite de gaz", strength=1.0)
    for _ in range(40):
        send(client, nose.read(tau=2.0))
    dets = client.get("/api/detections", params={"device_id": DEV}).json()
    assert any(d["label"] == "Fuite de gaz" for d in dets), dets
    assert dets[0]["room"] == "Cuisine" and dets[0]["lat"] == 48.85

    alerts = client.get("/api/alerts").json()
    assert any(a["level"] == "danger" for a in alerts)
    assert client.post("/api/alerts/ack-all").json()["acknowledged"] >= 1

    stats = client.get("/api/stats").json()
    assert stats["detections_total"] >= 1 and stats["devices_total"] == 1
    lib = {o["name"]: o for o in client.get("/api/odors").json()}
    assert lib["Café"]["samples"] == 10 and lib["Café"]["fingerprint"]["mq135"] > 0
    near = client.get("/api/detections/near", params={"lat": 48.85, "lon": 2.35, "radius_m": 100}).json()
    assert len(near) >= 1

    # Position réelle donnée depuis le téléphone : l'historique suit l'appareil
    client.patch(f"/api/devices/{DEV}", json={"lat": 18.0858, "lon": -15.9785, "move_history": True})
    moved = client.get("/api/detections", params={"device_id": DEV}).json()
    assert all(d["lat"] == 18.0858 and d["lon"] == -15.9785 for d in moved)


def test_odor_crud(client):
    r = client.post("/api/odors", json={"name": "Lavande", "icon": "💜", "color": "#9B7BFF"})
    assert r.status_code == 201
    oid = r.json()["id"]
    assert client.post("/api/odors", json={"name": "lavande"}).status_code == 409
    assert client.patch(f"/api/odors/{oid}", json={"alert_level": "info"}).json()["alert_level"] == "info"
    assert client.delete(f"/api/odors/{oid}").status_code == 204
    air = next(o for o in client.get("/api/odors").json() if o["is_air"])
    assert client.delete(f"/api/odors/{air['id']}").status_code == 400
