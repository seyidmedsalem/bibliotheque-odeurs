"""Configuration lue depuis les variables d'environnement (ou le fichier .env)."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", protected_namespaces=("settings_",))

    # Base de données : SQLite en local, PostgreSQL (TimescaleDB + PostGIS) dans Docker
    database_url: str = "sqlite:///./data/nez.db"

    # MQTT
    mqtt_enabled: bool = True
    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_user: str = ""
    mqtt_password: str = ""

    # Sécurité
    jwt_secret: str = "change-moi-en-production"
    jwt_expire_minutes: int = 60 * 24 * 7
    admin_email: str = "admin@nez.local"
    admin_password: str = "admin1234"
    ingest_key: str = "dev-ingest-key"  # clé pour POST /api/ingest (simulateur, appareils HTTP)

    # Machine learning
    model_path: str = "./data/model.joblib"
    window_size: int = 10          # nombre de mesures dans une fenêtre (10 s à 1 Hz)
    window_step: int = 5           # une prédiction toutes les 5 mesures
    confidence_threshold: float = 0.7
    detection_cooldown_s: int = 30

    # Alertes par règles (indépendantes du ML)
    mq4_danger_volts: float = 2.5
    voc_warning_index: int = 400
    rule_alert_cooldown_s: int = 300

    # Notifications Telegram (optionnel)
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""


settings = Settings()
