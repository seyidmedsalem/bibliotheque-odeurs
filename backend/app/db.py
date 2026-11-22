"""Connexion à la base, création des tables et extensions PostgreSQL."""
import logging
import os

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings

log = logging.getLogger(__name__)

IS_SQLITE = settings.database_url.startswith("sqlite")
if IS_SQLITE:
    path = settings.database_url.replace("sqlite:///", "")
    if path and path != ":memory:":
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)

engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if IS_SQLITE else {},
    pool_pre_ping=True,
)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _try(sql: str) -> bool:
    try:
        with engine.begin() as conn:
            conn.execute(text(sql))
        return True
    except Exception as exc:  # extension absente, déjà fait...
        log.info("SQL ignoré (%s) : %s", sql.split()[0:4], str(exc).splitlines()[0])
        return False


def init_db() -> None:
    from . import models  # noqa: F401  (enregistre les tables)

    if not IS_SQLITE:
        _try("CREATE EXTENSION IF NOT EXISTS timescaledb")
        _try("CREATE EXTENSION IF NOT EXISTS postgis")

    Base.metadata.create_all(engine)

    if IS_SQLITE:
        return

    # TimescaleDB : la table des mesures devient une « hypertable » partitionnée par le temps
    with engine.connect() as conn:
        try:
            is_hyper = conn.execute(text(
                "SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'measurements'"
            )).first() is not None
        except Exception:
            is_hyper = True  # pas de TimescaleDB : on ne fait rien
    if not is_hyper:
        _try("ALTER TABLE measurements DROP CONSTRAINT IF EXISTS measurements_pkey")
        _try("ALTER TABLE measurements ADD PRIMARY KEY (id, ts)")
        _try("SELECT create_hypertable('measurements', 'ts', if_not_exists => TRUE, migrate_data => TRUE)")
        _try("SELECT add_retention_policy('measurements', INTERVAL '90 days', if_not_exists => TRUE)")

    # PostGIS : colonne géographique calculée automatiquement à partir de lat / lon
    _try("""
        ALTER TABLE detections ADD COLUMN IF NOT EXISTS geom geography(Point, 4326)
        GENERATED ALWAYS AS (
            CASE WHEN lat IS NULL OR lon IS NULL THEN NULL
                 ELSE ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography END
        ) STORED
    """)
    _try("CREATE INDEX IF NOT EXISTS detections_geom_idx ON detections USING GIST (geom)")
