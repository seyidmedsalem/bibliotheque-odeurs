"""Transforme une fenêtre de mesures brutes en « empreinte olfactive ».

On n'utilise jamais les valeurs brutes : on mesure l'écart relatif à l'air de référence
(ΔR/R0), la pente (vitesse de montée) et le pic, pour chaque capteur de gaz.
"""
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

GAS_CHANNELS = ["bme688_gas", "sgp41_voc", "sgp41_nox", "ens160_tvoc", "mq3", "mq4", "mq135"]
ENV_CHANNELS = ["temp", "hum"]
ALL_CHANNELS = GAS_CHANNELS + ENV_CHANNELS + ["pressure", "ens160_eco2"]

FEATURE_NAMES = [f"{ch}_{k}" for ch in GAS_CHANNELS for k in ("mean", "slope", "peak")] + ENV_CHANNELS

CHANNEL_LABELS = {
    "bme688_gas": "BME688 gaz",
    "sgp41_voc": "SGP41 COV",
    "sgp41_nox": "SGP41 NOx",
    "ens160_tvoc": "ENS160 COVT",
    "mq3": "MQ-3 alcool",
    "mq4": "MQ-4 méthane",
    "mq135": "MQ-135 ammoniac",
}


def _num(value) -> Optional[float]:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and np.isfinite(value):
        return float(value)
    return None


def clean_reading(payload: dict) -> Dict[str, float]:
    """Garde uniquement les champs numériques connus d'un message capteur."""
    out = {}
    for ch in ALL_CHANNELS:
        v = _num(payload.get(ch))
        if v is not None:
            out[ch] = v
    return out


def channel_means(readings: Sequence[Dict[str, float]]) -> Dict[str, float]:
    means = {}
    for ch in GAS_CHANNELS + ENV_CHANNELS:
        vals = [r[ch] for r in readings if ch in r]
        if vals:
            means[ch] = float(np.mean(vals))
    return means


def compute_features(
    readings: Sequence[Dict[str, float]], baseline: Dict[str, float]
) -> Tuple[List[float], Dict[str, float]]:
    """Retourne (vecteur de caractéristiques pour le modèle, empreinte lisible pour l'interface)."""
    n = len(readings)
    t = np.arange(n, dtype=float)
    vector: List[float] = []
    fingerprint: Dict[str, float] = {}

    for ch in GAS_CHANNELS:
        base = baseline.get(ch)
        values = [r.get(ch) for r in readings]
        if base is None or all(v is None for v in values):
            vector += [0.0, 0.0, 0.0]
            continue
        arr = np.array([base if v is None else v for v in values], dtype=float)
        rel = (arr - base) / max(abs(base), 1e-6)
        mean = float(rel.mean())
        slope = float(np.polyfit(t, rel, 1)[0] * n) if n > 1 else 0.0
        peak = float(rel[int(np.argmax(np.abs(rel)))])
        vector += [mean, slope, peak]
        fingerprint[ch] = round(mean, 4)

    env = channel_means(readings)
    vector += [env.get("temp", 0.0), env.get("hum", 0.0)]
    return vector, fingerprint
