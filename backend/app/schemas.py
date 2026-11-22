"""Formats JSON de l'API (entrées et sorties)."""
from datetime import datetime, timezone
from typing import Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

ONLINE_TIMEOUT_S = 30


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------- auth
class LoginIn(BaseModel):
    email: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(ORM):
    id: int
    email: str


# ---------------------------------------------------------------- appareils
class DeviceOut(ORM):
    id: str
    name: str
    room: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None
    state: str
    last_seen: Optional[datetime] = None
    calibrated: bool = False
    online: bool = False

    @classmethod
    def build(cls, d) -> "DeviceOut":
        out = cls.model_validate(d)
        out.calibrated = bool(d.baseline)
        if d.last_seen is not None:
            seen = d.last_seen if d.last_seen.tzinfo else d.last_seen.replace(tzinfo=timezone.utc)
            out.online = (datetime.now(timezone.utc) - seen).total_seconds() < ONLINE_TIMEOUT_S and d.state != "offline"
        return out


class DeviceUpdate(BaseModel):
    name: Optional[str] = None
    room: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lon: Optional[float] = Field(None, ge=-180, le=180)
    move_history: bool = False  # déplacer aussi les anciennes détections vers la nouvelle position


class MeasurementOut(ORM):
    ts: datetime
    data: Dict[str, float]


# ---------------------------------------------------------------- odeurs
LEVELS = ("none", "info", "warning", "danger")


class OdorIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    icon: str = Field("👃", max_length=16)
    color: str = Field("#A98BFF", pattern=r"^#[0-9A-Fa-f]{6}$")
    alert_level: str = "none"
    description: Optional[str] = None

    @field_validator("alert_level")
    @classmethod
    def _level(cls, v: str) -> str:
        if v not in LEVELS:
            raise ValueError(f"alert_level doit être parmi {LEVELS}")
        return v


class OdorUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    icon: Optional[str] = Field(None, max_length=16)
    color: Optional[str] = Field(None, pattern=r"^#[0-9A-Fa-f]{6}$")
    alert_level: Optional[str] = None
    description: Optional[str] = None


class OdorOut(ORM):
    id: int
    name: str
    icon: str
    color: str
    alert_level: str
    description: Optional[str] = None
    is_air: bool
    samples: int = 0
    detections: int = 0
    fingerprint: Dict[str, float] = {}
    last_detected: Optional[datetime] = None


# ---------------------------------------------------------------- apprentissage
class SessionIn(BaseModel):
    device_id: str
    odor_id: int
    windows: int = Field(12, ge=3, le=200)
    skip_windows: int = Field(2, ge=0, le=20)


class SessionOut(ORM):
    id: int
    device_id: str
    odor_id: int
    target_windows: int
    skip_windows: int
    collected: int
    status: str
    created_at: datetime


class ModelInfo(BaseModel):
    trained: bool
    meta: dict = {}
    samples_per_odor: Dict[int, int] = {}


# ---------------------------------------------------------------- détections & alertes
class DetectionOut(ORM):
    id: int
    ts: datetime
    device_id: str
    odor_id: Optional[int] = None
    label: str
    confidence: float
    lat: Optional[float] = None
    lon: Optional[float] = None
    room: Optional[str] = None


class AlertOut(ORM):
    id: int
    ts: datetime
    device_id: str
    level: str
    title: str
    message: str
    odor_id: Optional[int] = None
    acknowledged: bool


class StatsOut(BaseModel):
    detections_day: int
    detections_total: int
    unacknowledged_alerts: int
    devices_online: int
    devices_total: int
    by_odor: List[dict]
    by_room: List[dict]
    timeline: List[dict]
