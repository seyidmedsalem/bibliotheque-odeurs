import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { relative, type Device } from "../api";
import { Empty, GlowBackground, GlowDot, Kicker, PageHeader, accent } from "../components/ui";
import { useStore } from "../store";

const STATE: Record<string, string> = { online: "en ligne", warming: "en chauffe", offline: "hors ligne" };

export default function Devices() {
  const s = useStore();
  useEffect(() => { s.loadHealth(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <>
      <GlowBackground colors={["var(--sky)", "var(--lilac)", "var(--mint)"]} />
      <PageHeader kicker={`${s.devices.filter((d) => d.online).length} en ligne`} title="Appareils" color="var(--sky)">
        <button className="ghost" onClick={s.logout}>Se déconnecter</button>
      </PageHeader>

      <div className="grid grid-2">
        <div className="stack">
          {!s.devices.length && <Empty title="Aucun appareil">Les nez apparaissent ici dès leur première mesure.</Empty>}
          {s.devices.map((d) => <DeviceCard key={d.id} device={d} />)}
        </div>
        <div className="stack">
          <div className="glass stack" style={{ gap: 10 }}>
            <Kicker color="var(--sky)">Serveur</Kicker>
            <Line label="Adresse" value={window.location.origin} />
            <Line label="Temps réel (WebSocket)" value={s.live ? "connecté" : "déconnecté"} ok={s.live} />
            <Line label="Broker MQTT" value={s.health?.mqtt_connected ? "connecté" : "non connecté"} ok={!!s.health?.mqtt_connected} />
            <Line label="Modèle" value={s.health?.model_trained ? "entraîné" : "non entraîné"} ok={!!s.health?.model_trained} />
            <a className="small" style={{ color: "var(--gold)" }} href="/docs" target="_blank" rel="noreferrer">Documentation de l'API (Swagger) ↗</a>
          </div>
          <div className="glass" style={{ textAlign: "center" }}>
            <div className="display" style={{ fontSize: 24 }}>La bibliothèque des odeurs</div>
            <div className="small" style={{ color: "var(--gold)", marginTop: 4 }}>Projet IoT de Seyid Cheikh</div>
          </div>
        </div>
      </div>
    </>
  );
}

function Line({ label, value, ok }: { label: string; value: string; ok?: boolean }) {
  return (
    <div className="row between small">
      <span className="muted">{label}</span>
      <span className="row" style={{ gap: 6 }}>{ok !== undefined && <GlowDot color={ok ? "var(--mint)" : "var(--muted)"} size={6} />}{value}</span>
    </div>
  );
}

function DeviceCard({ device }: { device: Device }) {
  const s = useStore();
  const [name, setName] = useState(device.name);
  const [room, setRoom] = useState(device.room ?? "");
  const [info, setInfo] = useState<string | null>(null);
  const dirty = name !== device.name || room !== (device.room ?? "");

  return (
    <div className="glass stack" style={{ gap: 14 }}>
      <div className="row between">
        <div className="row" style={{ gap: 10 }}>
          <GlowDot color={device.online ? "var(--mint)" : "var(--muted)"} />
          <div>
            <div style={{ fontWeight: 600 }}>{device.name}</div>
            <div className="muted small">{device.id} · {device.online ? STATE[device.state] ?? device.state : `vu ${relative(device.last_seen)}`}{device.calibrated ? " · calibré" : ""}</div>
          </div>
        </div>
      </div>
      <div className="grid grid-2" style={{ gridTemplateColumns: "1fr 1fr", gap: 10 }}>
        <div><label className="lbl">Nom</label><input className="input-box" value={name} onChange={(e) => setName(e.target.value)} /></div>
        <div><label className="lbl">Pièce</label><input className="input-box" placeholder="ex. Cuisine" value={room} onChange={(e) => setRoom(e.target.value)} /></div>
      </div>
      <div className="small">
        <span className="muted">Position réelle : </span>
        {device.lat !== null && device.lon !== null
          ? <span style={{ fontVariantNumeric: "tabular-nums" }}>{device.lat.toFixed(5)}, {device.lon.toFixed(5)}</span>
          : <span style={{ color: "var(--ember)" }}>non définie</span>}
        {" · "}<Link to="/carte" style={{ color: "var(--gold)" }}>placer sur la carte</Link>
      </div>
      <div className="row wrap">
        <button className="btn" disabled={!dirty} onClick={() => s.updateDevice(device.id, { name, room: room || null })}>Enregistrer</button>
        <button className="ghost" style={accent("var(--sky)")} onClick={async () => { await s.calibrate(device.id); setInfo("Calibration demandée : laissez le nez à l'air propre ~10 s."); }}>Calibrer à l'air propre</button>
        <button className="ghost" onClick={() => s.identify(device.id)}>Faire clignoter</button>
      </div>
      {info && <div className="muted small">{info}</div>}
    </div>
  );
}
