import { useState } from "react";
import { Area, AreaChart, Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { CHANNELS, parseDate, relative } from "../api";
import {
  ConfidenceRing, DevicePicker, Empty, GlowBackground, GlowDot, Kicker, LevelBadge, OdorIcon, PageHeader,
  ProbabilityBar, Radar, StatTile,
} from "../components/ui";
import { useStore } from "../store";

const fmt = (v: number) => (Math.abs(v) >= 1000 ? v.toFixed(0) : Math.abs(v) >= 10 ? v.toFixed(1) : v.toFixed(3));
const time = (s: string) => parseDate(s).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });

export default function Dashboard() {
  const s = useStore();
  const [channel, setChannel] = useState("sgp41_voc");
  const dev = s.selected;
  const p = dev ? s.predictions[dev.id] : undefined;
  const points = dev ? s.readings[dev.id] ?? [] : [];
  const color = p?.color ?? "#8E8E93";
  const last = points[points.length - 1];
  const ch = CHANNELS.find((c) => c.key === channel)!;
  const series = points.filter((r) => r.data[channel] !== undefined).map((r) => ({ t: time(r.ts), v: r.data[channel] }));

  return (
    <>
      <GlowBackground colors={[color, "var(--lilac)", "var(--mint)"]} />
      <PageHeader kicker="En direct" title="Le nez" color="var(--mint)"><DevicePicker /></PageHeader>

      {!s.devices.length ? (
        <Empty title="Aucun appareil">Branchez l'ESP32 ou lancez le simulateur : <code>python simulate.py live</code></Empty>
      ) : (
        <div className="stack">
          <div className="grid grid-2">
            {/* Odeur reconnue */}
            <div className="glass stack" style={{ gap: 16 }}>
              <div className="row between">
                <Kicker color={color}>Odeur reconnue</Kicker>
                <span className="row small muted" style={{ gap: 6 }}><GlowDot color={s.live ? "var(--mint)" : "var(--ember)"} size={6} />{s.live ? "temps réel" : "hors ligne"}</span>
              </div>
              <div className="row" style={{ gap: 18 }}>
                <OdorIcon icon={p?.icon ?? "👃"} color={color} size={72} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  {dev && s.warming[dev.id] ? (
                    <><div className="display" style={{ fontSize: 30 }}>Chauffe des capteurs…</div>
                      <div className="muted small">Les mesures seront fiables dans quelques minutes.</div></>
                  ) : (
                    <>
                      <div className="display" style={{ fontSize: "clamp(24px, 2.6vw, 38px)", lineHeight: 1.05, overflowWrap: "anywhere" }}>{p?.label ?? "En attente…"}</div>
                      <div className="row" style={{ gap: 8, marginTop: 8 }}>
                        {p && p.alert_level !== "none" && <LevelBadge level={p.alert_level} />}
                        <span className="muted small">{p ? relative(p.ts) : dev?.calibrated ? "Analyse de l'air en cours" : "Calibration à l'air propre…"}</span>
                      </div>
                    </>
                  )}
                </div>
                {p && (p.odor_id !== null || p.confidence > 0) && <ConfidenceRing value={p.confidence} color={color} size={78} />}
              </div>
              <div className="row muted small" style={{ gap: 18 }}>
                <span>⌂ {dev?.room ?? "Pièce non définie"}</span>
                {last && <><span>🌡 {last.data.temp?.toFixed(1)} °C</span><span>💧 {last.data.hum?.toFixed(0)} %</span></>}
              </div>
            </div>

            {/* Probabilités */}
            <div className="glass stack" style={{ gap: 14 }}>
              <Kicker color="var(--lilac)">Probabilités</Kicker>
              {p?.probabilities.length ? p.probabilities.slice(0, 5).map((x) =>
                <ProbabilityBar key={x.odor_id} label={x.label} value={x.p} color={x.color} />,
              ) : <div className="muted small">Entraînez le modèle (onglet Apprendre) pour voir les probabilités.</div>}
            </div>
          </div>

          <div className="grid grid-3">
            <StatTile value={s.stats?.detections_day ?? 0} label="détections sur 24 h" color="var(--gold)" />
            <StatTile value={s.unread} label="alertes non lues" color={s.unread ? "var(--ember)" : "var(--mint)"} />
            <StatTile value={`${s.devices.filter((d) => d.online).length}/${s.devices.length}`} label="appareils en ligne" color="var(--sky)" />
          </div>

          <div className="grid grid-2">
            <div className="glass">
              <Kicker>Empreinte olfactive</Kicker>
              <div className="muted small" style={{ margin: "6px 0 10px" }}>Écart de chaque capteur par rapport à l'air propre</div>
              <Radar fingerprint={p?.fingerprint ?? {}} color={color} size={300} />
            </div>

            <div className="glass stack" style={{ gap: 12 }}>
              <div className="row between">
                <Kicker color="var(--sky)">Capteur en direct</Kicker>
                {last?.data[channel] !== undefined && <span style={{ fontVariantNumeric: "tabular-nums" }}>{fmt(last.data[channel])} {ch.unit}</span>}
              </div>
              <div className="row wrap" style={{ gap: 6 }}>
                {CHANNELS.map((c) => (
                  <button key={c.key} className={`chip${c.key === channel ? " active" : ""}`} onClick={() => setChannel(c.key)}>{c.label}</button>
                ))}
              </div>
              <div style={{ height: 230 }}>
                {series.length < 2 ? <div className="muted small">Pas encore de mesures pour ce capteur.</div> : (
                  <ResponsiveContainer>
                    <AreaChart data={series} margin={{ top: 8, right: 4, left: -8, bottom: 0 }}>
                      <defs>
                        <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="var(--sky)" stopOpacity={0.4} /><stop offset="100%" stopColor="var(--sky)" stopOpacity={0} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid stroke="var(--hair)" vertical={false} />
                      <XAxis dataKey="t" tick={{ fill: "var(--muted)", fontSize: 11 }} minTickGap={40} stroke="transparent" />
                      <YAxis tick={{ fill: "var(--muted)", fontSize: 11 }} domain={["auto", "auto"]} stroke="transparent" width={56} tickFormatter={fmt} />
                      <Tooltip contentStyle={{ background: "var(--card)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: 12 }} formatter={(v: number) => [`${fmt(v)} ${ch.unit}`, ch.label]} />
                      <Area type="monotone" dataKey="v" stroke="var(--sky)" strokeWidth={2} fill="url(#g)" isAnimationActive={false} />
                    </AreaChart>
                  </ResponsiveContainer>
                )}
              </div>
            </div>
          </div>

          {s.stats && (
            <div className="glass">
              <Kicker color="var(--rose)">Détections des dernières 24 heures</Kicker>
              <div style={{ height: 170, marginTop: 12 }}>
                <ResponsiveContainer>
                  <BarChart data={s.stats.timeline} margin={{ top: 4, right: 4, left: -24, bottom: 0 }}>
                    <XAxis dataKey="hour" tick={{ fill: "var(--muted)", fontSize: 11 }} interval={2} stroke="transparent" />
                    <YAxis allowDecimals={false} tick={{ fill: "var(--muted)", fontSize: 11 }} stroke="transparent" />
                    <Tooltip cursor={{ fill: "var(--fill)" }} contentStyle={{ background: "var(--card)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: 12 }} />
                    <Bar dataKey="count" name="détections" fill="var(--rose)" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}
        </div>
      )}
    </>
  );
}
