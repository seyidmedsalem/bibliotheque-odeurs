import L from "leaflet";
import { useEffect, useMemo, useState } from "react";
import { Circle, CircleMarker, MapContainer, Marker, TileLayer, Tooltip, ZoomControl, useMap, useMapEvents } from "react-leaflet";
import { relative, type Detection, type Device } from "../api";
import { Kicker, ProbabilityBar, accent } from "../components/ui";
import { useStore } from "../store";

type Spot = { id: string; lat: number; lon: number; room: string | null; detections: Detection[]; counts: [number | null, number][] };
type Look = "satellite" | "plan";

const ESRI = "https://server.arcgisonline.com/ArcGIS/rest/services";
const ATTR_ESRI = "Imagerie © Esri, Maxar, Earthstar Geographics";

/** Recentre la carte sur les lieux connus, sinon sur la position du navigateur. */
function FitView({ points, user }: { points: [number, number][]; user: [number, number] | null }) {
  const map = useMap();
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (done) return;
    if (points.length) {
      map.fitBounds(L.latLngBounds(points).pad(0.4), { maxZoom: 18 });
      setDone(true);
    } else if (user) {
      map.setView(user, 17);
      setDone(true);
    }
  }, [points, user, done, map]);
  return null;
}

function ClickToPlace({ onPick }: { onPick: (lat: number, lon: number) => void }) {
  useMapEvents({ click: (e) => onPick(e.latlng.lat, e.latlng.lng) });
  return null;
}

function spotIcon(icon: string, color: string, count: number, selected: boolean) {
  const size = selected ? 46 : 38;
  return L.divIcon({
    className: "leaflet-div-icon clear",
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    html: `<div class="spot" style="width:${size}px;height:${size}px;border:2px solid ${color};box-shadow:0 0 12px ${color};font-size:${size * 0.48}px">${icon}${
      count > 1 ? `<span class="count" style="background:${color}">${count}</span>` : ""}</div>`,
  });
}

const deviceIcon = (online: boolean) => L.divIcon({
  className: "leaflet-div-icon clear", iconSize: [26, 26], iconAnchor: [13, -10],
  html: `<div style="width:26px;height:26px;border-radius:50%;display:grid;place-items:center;background:${online ? "#34C759" : "#8E8E93"};color:#fff;font-size:13px">⌁</div>`,
});

export default function MapPage() {
  const s = useStore();
  const [hours, setHours] = useState(24 * 7);
  const [filter, setFilter] = useState<number | null>(null);
  const [look, setLook] = useState<Look>("satellite");
  const [selected, setSelected] = useState<string | null>(null);
  const [user, setUser] = useState<[number, number] | null>(null);
  const [placing, setPlacing] = useState<Device | null>(null);
  const [pick, setPick] = useState<[number, number] | null>(null);
  const [moveHistory, setMoveHistory] = useState(true);
  const [geoError, setGeoError] = useState<string | null>(null);

  useEffect(() => { s.loadDetections(hours); }, [hours]); // eslint-disable-line react-hooks/exhaustive-deps

  const locate = (then?: (p: [number, number]) => void) => {
    if (!navigator.geolocation) { setGeoError("Ce navigateur ne donne pas la position."); return; }
    navigator.geolocation.getCurrentPosition(
      (pos) => { const p: [number, number] = [pos.coords.latitude, pos.coords.longitude]; setUser(p); setGeoError(null); then?.(p); },
      () => setGeoError("Position indisponible (autorisez la localisation ; elle n'est permise qu'en https ou sur localhost)."),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  };
  useEffect(() => { locate(); }, []);

  const spots: Spot[] = useMemo(() => {
    const groups = new Map<string, Detection[]>();
    for (const d of s.detections) {
      if (d.lat === null || d.lon === null || (filter !== null && d.odor_id !== filter)) continue;
      const key = `${d.lat.toFixed(5)},${d.lon.toFixed(5)}`;
      groups.set(key, [...(groups.get(key) ?? []), d]);
    }
    return [...groups].map(([id, list]) => {
      const c = new Map<number | null, number>();
      list.forEach((d) => c.set(d.odor_id, (c.get(d.odor_id) ?? 0) + 1));
      return { id, lat: list[0].lat!, lon: list[0].lon!, room: list[0].room, detections: list, counts: [...c].sort((a, b) => b[1] - a[1]) };
    });
  }, [s.detections, filter]);

  const placed = s.devices.filter((d) => d.lat !== null && d.lon !== null);
  const unplaced = s.devices.filter((d) => d.lat === null || d.lon === null);
  const points: [number, number][] = [...spots.map((p) => [p.lat, p.lon] as [number, number]), ...placed.map((d) => [d.lat!, d.lon!] as [number, number])];
  const sel = spots.find((p) => p.id === selected);
  const total = spots.reduce((n, p) => n + p.detections.length, 0);

  const startPlacing = (d: Device) => { setPlacing(d); setPick(d.lat !== null && d.lon !== null ? [d.lat, d.lon] : null); setSelected(null); };
  const savePlace = async () => {
    if (!placing || !pick) return;
    await s.updateDevice(placing.id, { lat: pick[0], lon: pick[1], move_history: moveHistory });
    setPlacing(null); setPick(null);
  };

  return (
    <div className="map-page">
      <MapContainer center={[20, 0]} zoom={2} zoomControl={false} style={{ cursor: placing ? "crosshair" : undefined }}>
        {look === "satellite" ? (
          <>
            <TileLayer url={`${ESRI}/World_Imagery/MapServer/tile/{z}/{y}/{x}`} attribution={ATTR_ESRI} maxZoom={20} maxNativeZoom={19} />
            <TileLayer url={`${ESRI}/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}`} maxZoom={20} maxNativeZoom={19} opacity={0.7} />
            <TileLayer url={`${ESRI}/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}`} maxZoom={20} maxNativeZoom={19} />
          </>
        ) : (
          <TileLayer url={`https://{s}.basemaps.cartocdn.com/${window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark_all" : "voyager"}/{z}/{x}/{y}{r}.png`} maxZoom={20}
            attribution='© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> · © <a href="https://carto.com/">CARTO</a>' />
        )}
        <ZoomControl position="bottomright" />
        <FitView points={points} user={user} />
        {placing && <ClickToPlace onPick={(lat, lon) => setPick([lat, lon])} />}

        {user && <CircleMarker center={user} radius={7} pathOptions={{ color: "white", weight: 2, fillColor: "#2E86FF", fillOpacity: 1 }}><Tooltip>Vous êtes ici</Tooltip></CircleMarker>}

        {!placing && spots.map((p) => {
          const top = s.odor(p.counts[0][0]);
          const color = top?.color ?? "#8A8494";
          return (
            <div key={p.id}>
              <Circle center={[p.lat, p.lon]} radius={6 + 3 * Math.min(p.detections.length, 12)} pathOptions={{ color, weight: 1, fillColor: color, fillOpacity: 0.25 }} />
              <Marker position={[p.lat, p.lon]} icon={spotIcon(top?.icon ?? "❔", color, p.detections.length, selected === p.id)}
                eventHandlers={{ click: () => setSelected(p.id) }} />
            </div>
          );
        })}
        {placed.map((d) => (
          <Marker key={d.id} position={[d.lat!, d.lon!]} icon={deviceIcon(d.online)} eventHandlers={{ click: () => startPlacing(d) }}>
            <Tooltip direction="bottom" offset={[0, 30]}>{d.name} · cliquer pour déplacer</Tooltip>
          </Marker>
        ))}
        {placing && pick && <Marker position={pick} icon={deviceIcon(true)} />}
      </MapContainer>

      {/* En-tête */}
      <div className="map-overlay" style={{ top: 16 }}>
        <div className="map-panel stack" style={{ gap: 10 }}>
          <div className="row between wrap">
            <div className="display" style={{ fontSize: 28 }}>Carte olfactive</div>
            <div className="row wrap" style={{ gap: 6 }}>
              {(["satellite", "plan"] as Look[]).map((l) => (
                <button key={l} className={`chip${look === l ? " active" : ""}`} onClick={() => setLook(l)}>{l === "satellite" ? "Satellite" : "Plan"}</button>
              ))}
              <span style={{ width: 8 }} />
              {[[24, "24 h"], [24 * 7, "7 j"], [24 * 30, "30 j"]].map(([h, t]) => (
                <button key={h} className={`chip${hours === h ? " active" : ""}`} onClick={() => setHours(h as number)}>{t}</button>
              ))}
              <button className="chip" onClick={() => locate()} title="Ma position">◉ Ma position</button>
            </div>
          </div>
          <div className="row" style={{ gap: 6, overflowX: "auto" }}>
            <button className={`chip${filter === null ? " active" : ""}`} onClick={() => setFilter(null)}>Toutes</button>
            {s.odors.filter((o) => !o.is_air).map((o) => (
              <button key={o.id} className={`chip${filter === o.id ? " active" : ""}`} style={accent(o.color)} onClick={() => setFilter(o.id)}>{o.icon} {o.name}</button>
            ))}
          </div>
          {unplaced.length > 0 && !placing && (
            <div className="row wrap small" style={{ gap: 8, color: "var(--ember)" }}>
              ⚑ {unplaced.length} appareil(s) sans position réelle :
              {unplaced.map((d) => <button key={d.id} className="ghost" style={accent("var(--ember)")} onClick={() => startPlacing(d)}>Placer {d.name}</button>)}
            </div>
          )}
          {geoError && <div className="small muted">{geoError}</div>}
        </div>
      </div>

      {/* Bas : placement, détail d'un lieu ou résumé */}
      <div className="map-overlay" style={{ bottom: 16, maxWidth: 520 }}>
        {placing ? (
          <div className="map-panel stack" style={{ gap: 10, borderColor: "var(--mint)" }}>
            <Kicker color="var(--mint)">Placer « {placing.name} »</Kicker>
            <div className="muted small">Cliquez sur la carte à l'endroit exact où se trouve le nez, ou utilisez votre position actuelle.</div>
            <div className="row wrap">
              <button className="ghost" style={accent("var(--sky)")} onClick={() => locate((p) => setPick(p))}>◉ Utiliser ma position</button>
              <label className="row small" style={{ gap: 6, cursor: "pointer" }}>
                <input type="checkbox" checked={moveHistory} onChange={(e) => setMoveHistory(e.target.checked)} /> Déplacer aussi ses anciennes détections
              </label>
            </div>
            {pick && <div className="muted small" style={{ fontVariantNumeric: "tabular-nums" }}>{pick[0].toFixed(6)}, {pick[1].toFixed(6)}</div>}
            <div className="row">
              <button className="btn" style={accent("var(--mint)")} disabled={!pick} onClick={savePlace}>Enregistrer la position</button>
              <button className="ghost" onClick={() => { setPlacing(null); setPick(null); }}>Annuler</button>
            </div>
          </div>
        ) : sel ? (
          <div className="map-panel stack" style={{ gap: 10, borderColor: "rgba(232,194,122,0.5)" }}>
            <div className="row between">
              <div>
                <div className="display" style={{ fontSize: 26 }}>{sel.room ?? "Lieu"}</div>
                <div className="muted small" style={{ fontVariantNumeric: "tabular-nums" }}>{sel.lat.toFixed(5)}, {sel.lon.toFixed(5)}</div>
              </div>
              <button className="icon-btn" onClick={() => setSelected(null)}>×</button>
            </div>
            {sel.counts.slice(0, 4).map(([oid, n]) => {
              const o = s.odor(oid);
              return <ProbabilityBar key={String(oid)} label={`${o?.icon ?? "❔"} ${o?.name ?? "Inconnue"}`} value={n / sel.detections.length} color={o?.color ?? "#8A8494"} />;
            })}
            <div className="muted small">Dernière : {sel.detections[0].label} {relative(sel.detections[0].ts)} · {Math.round(sel.detections[0].confidence * 100)} %</div>
          </div>
        ) : (
          <div className="map-panel stack" style={{ gap: 8 }}>
            <div className="row between"><Kicker>Par lieu</Kicker><span className="muted small">{total} détections · {spots.length} lieux</span></div>
            {!spots.length && <div className="muted small">Aucune détection géolocalisée sur cette période. Placez vos appareils à leur vraie position.</div>}
            {[...spots].sort((a, b) => b.detections.length - a.detections.length).slice(0, 4).map((p) => {
              const o = s.odor(p.counts[0][0]);
              return (
                <button key={p.id} className="row between" style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }} onClick={() => setSelected(p.id)}>
                  <span style={{ fontWeight: 500 }}>{p.room ?? "Lieu sans nom"}</span>
                  <span className="row small" style={{ gap: 12 }}>
                    <span style={{ color: o?.color }}>{o?.icon} {o?.name}</span>
                    <span className="muted" style={{ width: 28, textAlign: "right" }}>{p.detections.length}</span>
                  </span>
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
