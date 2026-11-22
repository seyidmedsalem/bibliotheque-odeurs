"""Tables de la base de données."""
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import JSON, BigInteger, Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    room: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    lat: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    lon: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    state: Mapped[str] = mapped_column(String(20), default="unknown")  # online, offline, warming
    last_seen: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    baseline: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)  # air de référence
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Odor(Base):
    __tablename__ = "odors"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)
    icon: Mapped[str] = mapped_column(String(16), default="👃")
    color: Mapped[str] = mapped_column(String(9), default="#A98BFF")
    alert_level: Mapped[str] = mapped_column(String(10), default="none")  # none, info, warning, danger
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_air: Mapped[bool] = mapped_column(Boolean, default=False)  # classe « air ambiant »
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Measurement(Base):
    """Mesure brute (une par seconde et par appareil). Hypertable TimescaleDB en production."""
    __tablename__ = "measurements"
    id: Mapped[int] = mapped_column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True)
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    data: Mapped[dict] = mapped_column(JSON)


class TrainingSession(Base):
    __tablename__ = "training_sessions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    odor_id: Mapped[int] = mapped_column(ForeignKey("odors.id", ondelete="CASCADE"))
    target_windows: Mapped[int] = mapped_column(Integer, default=12)
    skip_windows: Mapped[int] = mapped_column(Integer, default=2)  # fenêtres ignorées au début (montée)
    collected: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(12), default="active")  # active, done, cancelled
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class TrainingSample(Base):
    """Une empreinte olfactive étiquetée, utilisée pour entraîner le modèle."""
    __tablename__ = "training_samples"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    odor_id: Mapped[int] = mapped_column(ForeignKey("odors.id", ondelete="CASCADE"), index=True)
    device_id: Mapped[str] = mapped_column(String(64))
    session_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    features: Mapped[list] = mapped_column(JSON)
    fingerprint: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Detection(Base):
    """Une odeur reconnue, horodatée et géolocalisée → carte olfactive."""
    __tablename__ = "detections"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    odor_id: Mapped[Optional[int]] = mapped_column(ForeignKey("odors.id", ondelete="SET NULL"), nullable=True, index=True)
    label: Mapped[str] = mapped_column(String(120))
    confidence: Mapped[float] = mapped_column(Float)
    lat: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    lon: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    room: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)


class Alert(Base):
    __tablename__ = "alerts"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    device_id: Mapped[str] = mapped_column(String(64))
    level: Mapped[str] = mapped_column(String(10))  # info, warning, danger
    title: Mapped[str] = mapped_column(String(200))
    message: Mapped[str] = mapped_column(Text)
    odor_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)
