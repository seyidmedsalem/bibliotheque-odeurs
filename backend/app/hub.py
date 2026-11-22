"""Le « Hub » relie le monde asynchrone (MQTT, WebSocket, Telegram) au Processor synchrone."""
import asyncio
import json
import logging
from typing import List, Optional, Set

import aiomqtt
import httpx
from fastapi import WebSocket

from .config import settings
from .processing import Processor

log = logging.getLogger(__name__)


class Hub:
    def __init__(self, processor: Processor):
        self.processor = processor
        self.sockets: Set[WebSocket] = set()
        self.mqtt: Optional[aiomqtt.Client] = None

    @property
    def mqtt_connected(self) -> bool:
        return self.mqtt is not None

    # ---------------------------------------------------------------- WebSocket
    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self.sockets.add(ws)
        for event in self.processor.last_predictions():
            await ws.send_json(event)

    def disconnect(self, ws: WebSocket) -> None:
        self.sockets.discard(ws)

    async def broadcast(self, events: List[dict]) -> None:
        for event in events:
            dead = []
            for ws in list(self.sockets):
                try:
                    await ws.send_json(event)
                except Exception:
                    dead.append(ws)
            for ws in dead:
                self.sockets.discard(ws)

    # ---------------------------------------------------------------- MQTT
    async def publish(self, topic: str, payload: dict) -> bool:
        if self.mqtt is None:
            return False
        try:
            await self.mqtt.publish(topic, json.dumps(payload, ensure_ascii=False))
            return True
        except aiomqtt.MqttError as exc:
            log.warning("Publication MQTT impossible : %s", exc)
            return False

    async def send_command(self, device_id: str, payload: dict) -> bool:
        return await self.publish(f"nose/{device_id}/cmd", payload)

    # ---------------------------------------------------------------- entrées
    async def handle_reading(self, device_id: str, payload: dict) -> None:
        events, mqtt_out = await asyncio.to_thread(self.processor.handle_reading, device_id, payload)
        await self.broadcast(events)
        for topic, msg in mqtt_out:
            await self.publish(topic, msg)
        for event in events:
            if event["type"] == "alert":
                asyncio.create_task(self.notify(event["alert"]))

    async def handle_status(self, device_id: str, payload: dict) -> None:
        events = await asyncio.to_thread(self.processor.handle_status, device_id, payload)
        await self.broadcast(events)

    async def notify(self, alert: dict) -> None:
        """Envoie l'alerte sur Telegram si un bot est configuré."""
        if not (settings.telegram_bot_token and settings.telegram_chat_id):
            return
        icon = {"danger": "🚨", "warning": "⚠️"}.get(alert["level"], "ℹ️")
        text = f"{icon} {alert['title']}\n{alert['message']}"
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                await client.post(f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage",
                                  json={"chat_id": settings.telegram_chat_id, "text": text})
        except httpx.HTTPError as exc:
            log.warning("Telegram indisponible : %s", exc)

    async def mqtt_loop(self) -> None:
        """Reste connecté au broker et traite les messages nose/+/raw et nose/+/status."""
        while True:
            try:
                async with aiomqtt.Client(
                    settings.mqtt_host, settings.mqtt_port, identifier="nez-backend",
                    username=settings.mqtt_user or None, password=settings.mqtt_password or None,
                ) as client:
                    self.mqtt = client
                    await client.subscribe("nose/+/raw")
                    await client.subscribe("nose/+/status")
                    log.info("MQTT connecté à %s:%s", settings.mqtt_host, settings.mqtt_port)
                    async for message in client.messages:
                        await self._on_message(str(message.topic), message.payload)
            except aiomqtt.MqttError as exc:
                log.warning("MQTT déconnecté (%s), nouvel essai dans 5 s", exc)
            finally:
                self.mqtt = None
            await asyncio.sleep(5)

    async def _on_message(self, topic: str, raw) -> None:
        parts = topic.split("/")
        if len(parts) != 3:
            return
        _, device_id, kind = parts
        try:
            payload = json.loads(raw)
        except (TypeError, ValueError):
            log.warning("Message illisible sur %s", topic)
            return
        try:
            if kind == "raw":
                await self.handle_reading(device_id, payload)
            elif kind == "status":
                await self.handle_status(device_id, payload)
        except Exception:
            log.exception("Erreur pendant le traitement de %s", topic)
