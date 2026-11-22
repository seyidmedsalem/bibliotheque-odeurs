"""Cœur du système : chaque mesure reçue passe par ici.

mesure → stockage → fenêtre glissante → empreinte → (apprentissage | prédiction) → détection / alerte

Cette classe est synchrone et sans réseau : elle retourne des événements (pour le WebSocket)
et des messages MQTT à publier. C'est le « Hub » qui s'occupe de les envoyer.
"""
import logging
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Deque, Dict, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .features import channel_means, clean_reading, compute_features
from .ml import OdorModel
from .models import Alert, Detection, Device, Measurement, Odor, TrainingSample, TrainingSession
from .schemas import AlertOut, DetectionOut, DeviceOut, SessionOut

log = logging.getLogger(__name__)

UNKNOWN_LABEL = "Odeur inconnue"
UNKNOWN_COLOR = "#8A8494"
BASELINE_ALPHA_AIR = 0.10       # adaptation de la référence quand l'air est reconnu comme propre
BASELINE_ALPHA_NO_MODEL = 0.02  # adaptation lente tant qu'il n'y a pas de modèle

Event = dict
MqttMsg = Tuple[str, dict]


@dataclass
class DeviceState:
    buffer: Deque[Dict[str, float]] = field(default_factory=lambda: deque(maxlen=settings.window_size))
    since_last: int = 0
    calibrate_pending: bool = False
    last_detection: Tuple[Optional[int], float] = (None, 0.0)
    rule_cooldowns: Dict[str, float] = field(default_factory=dict)
    last_prediction: Optional[Event] = None


class Processor:
    def __init__(self, session_factory, model: OdorModel):
        self.session_factory = session_factory
        self.model = model
        self.states: Dict[str, DeviceState] = {}
        self._lock = threading.Lock()

    def state(self, device_id: str) -> DeviceState:
        if device_id not in self.states:
            self.states[device_id] = DeviceState()
        return self.states[device_id]

    def request_calibration(self, device_id: str) -> None:
        with self._lock:
            st = self.state(device_id)
            st.calibrate_pending = True
            st.buffer.clear()
            st.since_last = 0

    def last_predictions(self) -> List[Event]:
        return [s.last_prediction for s in self.states.values() if s.last_prediction]

    # ------------------------------------------------------------------ statut
    def handle_status(self, device_id: str, payload: dict) -> List[Event]:
        with self._lock, self.session_factory() as db:
            dev = self._get_device(db, device_id)
            dev.state = str(payload.get("state", "online"))[:20]
            if dev.state != "offline":
                dev.last_seen = datetime.now(timezone.utc)
            db.commit()
            return [{"type": "device", "device": DeviceOut.build(dev).model_dump(mode="json")}]

    # ------------------------------------------------------------------ mesures
    def handle_reading(self, device_id: str, payload: dict) -> Tuple[List[Event], List[MqttMsg]]:
        with self._lock, self.session_factory() as db:
            events: List[Event] = []
            mqtt_out: List[MqttMsg] = []
            now = datetime.now(timezone.utc)
            reading = clean_reading(payload)
            warming = bool(payload.get("warming", False))

            dev = self._get_device(db, device_id)
            was_online = DeviceOut.build(dev).online
            dev.last_seen = now
            dev.state = "warming" if warming else "online"
            lat, lon = payload.get("lat"), payload.get("lon")
            if isinstance(lat, (int, float)) and isinstance(lon, (int, float)) and (lat or lon):
                dev.lat, dev.lon = float(lat), float(lon)

            db.add(Measurement(ts=now, device_id=device_id, data=reading))
            db.commit()
            if not was_online:
                events.append({"type": "device", "device": DeviceOut.build(dev).model_dump(mode="json")})
            events.append({"type": "reading", "device_id": device_id, "ts": now.isoformat(),
                           "warming": warming, "data": reading})

            if warming or not reading:
                return events, mqtt_out

            st = self.state(device_id)
            st.buffer.append(reading)
            st.since_last += 1
            if len(st.buffer) < settings.window_size or st.since_last < settings.window_step:
                return events, mqtt_out
            st.since_last = 0
            window = list(st.buffer)

            # 1) Calibration : la fenêtre actuelle devient l'air de référence
            if not dev.baseline or st.calibrate_pending:
                dev.baseline = channel_means(window)
                st.calibrate_pending = False
                db.commit()
                events.append({"type": "calibrated", "device_id": device_id, "baseline": dev.baseline})
                return events, mqtt_out

            features, fingerprint = compute_features(window, dev.baseline)

            # 2) Session d'apprentissage en cours → on enregistre un échantillon étiqueté
            session = db.scalars(select(TrainingSession).where(
                TrainingSession.device_id == device_id, TrainingSession.status == "active"
            ).order_by(TrainingSession.id.desc())).first()
            if session is not None:
                self._collect_sample(db, session, features, fingerprint, events, mqtt_out)
                return events, mqtt_out

            # 3) Alertes par règles simples (sécurité, indépendantes du ML)
            self._rule_alerts(db, dev, st, reading, events)

            # 4) Prédiction
            self._predict(db, dev, st, window, features, fingerprint, events, mqtt_out)
            db.commit()
            return events, mqtt_out

    # ------------------------------------------------------------------ étapes
    def _get_device(self, db: Session, device_id: str) -> Device:
        dev = db.get(Device, device_id)
        if dev is None:
            dev = Device(id=device_id, name=device_id, state="online")
            db.add(dev)
            db.flush()
        return dev

    def _collect_sample(self, db, session, features, fingerprint, events, mqtt_out) -> None:
        if session.skip_windows > 0:
            session.skip_windows -= 1  # on laisse le temps à l'odeur de monter
        else:
            db.add(TrainingSample(odor_id=session.odor_id, device_id=session.device_id,
                                  session_id=session.id, features=features, fingerprint=fingerprint))
            session.collected += 1
            if session.collected >= session.target_windows:
                session.status = "done"
                mqtt_out.append((f"nose/{session.device_id}/cmd", {"cmd": "learn_done"}))
        db.commit()
        events.append({"type": "training_progress", "session": SessionOut.model_validate(session).model_dump(mode="json"),
                       "fingerprint": fingerprint})

    def _rule_alerts(self, db, dev, st, reading, events) -> None:
        rules = []
        if reading.get("mq4", 0) >= settings.mq4_danger_volts:
            rules.append(("mq4", "danger", "Niveau de méthane élevé",
                          f"Le capteur MQ-4 indique {reading['mq4']:.2f} V. Aérez et vérifiez l'arrivée de gaz."))
        if reading.get("sgp41_voc", 0) >= settings.voc_warning_index:
            rules.append(("voc", "warning", "Air très chargé en COV",
                          f"Indice COV {reading['sgp41_voc']:.0f} / 500. Pensez à aérer."))
        now = time.time()
        for key, level, title, msg in rules:
            if now - st.rule_cooldowns.get(key, 0) < settings.rule_alert_cooldown_s:
                continue
            st.rule_cooldowns[key] = now
            alert = Alert(device_id=dev.id, level=level, title=f"{title} ({dev.name})", message=msg)
            db.add(alert)
            db.flush()
            events.append({"type": "alert", "alert": AlertOut.model_validate(alert).model_dump(mode="json")})

    def _predict(self, db, dev, st, window, features, fingerprint, events, mqtt_out) -> None:
        if not self.model.trained:
            self._adapt_baseline(dev, window, BASELINE_ALPHA_NO_MODEL)
            event = {"type": "prediction", "device_id": dev.id, "odor_id": None, "label": "Modèle non entraîné",
                     "confidence": 0.0, "color": UNKNOWN_COLOR, "icon": "❔", "alert_level": "none",
                     "probabilities": [], "fingerprint": fingerprint, "ts": datetime.now(timezone.utc).isoformat()}
            st.last_prediction = event
            events.append(event)
            return

        odor_id, conf, ranked = self.model.predict(features)
        odors = {o.id: o for o in db.scalars(select(Odor)).all()}
        odor = odors.get(odor_id) if conf >= settings.confidence_threshold else None

        probabilities = [{"odor_id": oid, "label": odors[oid].name, "color": odors[oid].color, "p": round(p, 4)}
                         for oid, p in ranked if oid in odors]
        event = {
            "type": "prediction", "device_id": dev.id,
            "odor_id": odor.id if odor else None,
            "label": odor.name if odor else UNKNOWN_LABEL,
            "confidence": round(conf, 4),
            "color": odor.color if odor else UNKNOWN_COLOR,
            "icon": odor.icon if odor else "❔",
            "alert_level": odor.alert_level if odor else "none",
            "probabilities": probabilities, "fingerprint": fingerprint,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        st.last_prediction = event
        events.append(event)
        mqtt_out.append((f"nose/{dev.id}/prediction", {k: event[k] for k in ("label", "confidence", "color", "alert_level")}))

        if odor is None:
            return
        if odor.is_air:
            self._adapt_baseline(dev, window, BASELINE_ALPHA_AIR)
            st.last_detection = (None, 0.0)
            return

        # Nouvelle détection (pas de doublon pour la même odeur pendant le délai d'attente)
        last_id, last_t = st.last_detection
        now = time.time()
        if last_id == odor.id and now - last_t < settings.detection_cooldown_s:
            return
        st.last_detection = (odor.id, now)
        det = Detection(device_id=dev.id, odor_id=odor.id, label=odor.name, confidence=conf,
                        lat=dev.lat, lon=dev.lon, room=dev.room)
        db.add(det)
        db.flush()
        events.append({"type": "detection", "detection": DetectionOut.model_validate(det).model_dump(mode="json"),
                       "color": odor.color, "icon": odor.icon})

        if odor.alert_level != "none":
            where = f" ({dev.room})" if dev.room else ""
            alert = Alert(device_id=dev.id, level=odor.alert_level, odor_id=odor.id,
                          title=f"{odor.icon} {odor.name} détecté{where}",
                          message=f"{dev.name} a reconnu « {odor.name} » avec {conf * 100:.0f} % de confiance.")
            db.add(alert)
            db.flush()
            events.append({"type": "alert", "alert": AlertOut.model_validate(alert).model_dump(mode="json")})

    @staticmethod
    def _adapt_baseline(dev: Device, window, alpha: float) -> None:
        """Suit lentement la dérive des capteurs (moyenne mobile exponentielle)."""
        means = channel_means(window)
        base = dict(dev.baseline or {})
        for ch, v in means.items():
            base[ch] = v if ch not in base else (1 - alpha) * base[ch] + alpha * v
        dev.baseline = base
