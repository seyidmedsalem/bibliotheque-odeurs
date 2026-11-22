"""Modèle de reconnaissance d'odeurs : Random Forest (scikit-learn)."""
import os
import threading
from collections import Counter
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence, Tuple

import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, confusion_matrix
from sklearn.model_selection import StratifiedKFold, cross_val_predict
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from .features import FEATURE_NAMES

MIN_SAMPLES_PER_CLASS = 3


class TrainingError(ValueError):
    pass


def _make_pipeline() -> Pipeline:
    return Pipeline([
        ("scale", StandardScaler()),
        ("forest", RandomForestClassifier(n_estimators=200, class_weight="balanced", random_state=42)),
    ])


class OdorModel:
    def __init__(self, path: str):
        self.path = path
        self.pipeline: Optional[Pipeline] = None
        self.meta: Dict = {}
        self._lock = threading.Lock()
        self.load()

    @property
    def trained(self) -> bool:
        return self.pipeline is not None

    def load(self) -> None:
        if os.path.exists(self.path):
            data = joblib.load(self.path)
            if data.get("feature_names") == FEATURE_NAMES:
                self.pipeline, self.meta = data["pipeline"], data["meta"]

    def reset(self) -> None:
        with self._lock:
            self.pipeline, self.meta = None, {}
            if os.path.exists(self.path):
                os.remove(self.path)

    def train(self, X: Sequence[Sequence[float]], y: Sequence[int], names: Dict[int, str]) -> Dict:
        counts = Counter(y)
        if len(counts) < 2:
            raise TrainingError("Il faut au moins 2 odeurs différentes (par exemple « Air ambiant » + une odeur).")
        small = [names.get(k, str(k)) for k, n in counts.items() if n < MIN_SAMPLES_PER_CLASS]
        if small:
            raise TrainingError(f"Pas assez d'échantillons (minimum {MIN_SAMPLES_PER_CLASS}) pour : {', '.join(small)}")

        X_arr, y_arr = np.asarray(X, dtype=float), np.asarray(y)
        labels = sorted(counts)

        # Validation croisée : estimation honnête de la précision sur des données jamais vues
        k = min(5, min(counts.values()))
        cv = StratifiedKFold(n_splits=k, shuffle=True, random_state=42)
        y_pred = cross_val_predict(_make_pipeline(), X_arr, y_arr, cv=cv)
        accuracy = float(accuracy_score(y_arr, y_pred))
        cm = confusion_matrix(y_arr, y_pred, labels=labels).tolist()

        pipeline = _make_pipeline().fit(X_arr, y_arr)
        importances = pipeline.named_steps["forest"].feature_importances_
        top = sorted(zip(FEATURE_NAMES, importances), key=lambda p: -p[1])[:8]

        meta = {
            "trained_at": datetime.now(timezone.utc).isoformat(),
            "n_samples": int(len(y_arr)),
            "accuracy": round(accuracy, 4),
            "cv_folds": k,
            "classes": [{"odor_id": int(c), "name": names.get(c, str(c)), "samples": int(counts[c])} for c in labels],
            "confusion_matrix": cm,
            "top_features": [{"feature": f, "importance": round(float(v), 4)} for f, v in top],
        }
        with self._lock:
            self.pipeline, self.meta = pipeline, meta
            os.makedirs(os.path.dirname(os.path.abspath(self.path)), exist_ok=True)
            joblib.dump({"pipeline": pipeline, "meta": meta, "feature_names": FEATURE_NAMES}, self.path)
        return meta

    def predict(self, features: Sequence[float]) -> Tuple[int, float, List[Tuple[int, float]]]:
        """Retourne (id de l'odeur la plus probable, confiance, liste triée des probabilités)."""
        with self._lock:
            pipeline = self.pipeline
        if pipeline is None:
            raise RuntimeError("Modèle non entraîné")
        proba = pipeline.predict_proba(np.asarray([features], dtype=float))[0]
        classes = pipeline.classes_
        ranked = sorted(((int(c), float(p)) for c, p in zip(classes, proba)), key=lambda p: -p[1])
        return ranked[0][0], ranked[0][1], ranked
