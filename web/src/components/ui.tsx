import type { CSSProperties, ReactNode } from "react";
import { CHANNELS, LEVELS } from "../api";
import { useStore } from "../store";

export const accent = (color: string) => ({ "--accent": color }) as CSSProperties;

export function GlowBackground({ colors }: { colors: string[] }) {
  return (
    <div className="glow-bg">
      {colors.slice(0, 3).map((c, i) => <span key={i} style={{ background: c }} />)}
    </div>
  );
}

export function PageHeader({ kicker, title, color = "var(--gold)", children }: { kicker: string; title: string; color?: string; children?: ReactNode }) {
  return (
    <div className="page-header">
      <div>
        <div className="kicker" style={{ color }}>{kicker}</div>
        <h1>{title}</h1>
        <div className="rule" style={{ background: color }} />
      </div>
      {children && <div className="row wrap">{children}</div>}
    </div>
  );
}

export function Kicker({ children, color = "var(--gold)" }: { children: ReactNode; color?: string }) {
  return <div className="kicker" style={{ color }}>{children}</div>;
}

export function GlowDot({ color, size = 9 }: { color: string; size?: number }) {
  return <span className="dot" style={{ background: color, width: size, height: size, boxShadow: `0 0 ${size}px ${color}` }} />;
}

export function OdorIcon({ icon, color, size = 44 }: { icon: string; color: string; size?: number }) {
  return (
    <div className="odor-icon" style={{
      width: size, height: size, fontSize: size * 0.48, background: `${color}2e`,
      border: `1px solid ${color}b3`, boxShadow: `0 0 ${size * 0.35}px ${color}88`,
    }}>{icon}</div>
  );
}

export function LevelBadge({ level }: { level: string }) {
  const l = LEVELS[level] ?? LEVELS.none;
  return <span className="level" style={{ color: l.color, background: `${l.color}24` }}>{l.name}</span>;
}

export function ProbabilityBar({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div>
      <div className="row between" style={{ marginBottom: 5 }}>
        <span style={{ fontSize: 14 }}>{label}</span>
        <span className="muted small" style={{ fontVariantNumeric: "tabular-nums" }}>{Math.round(value * 100)} %</span>
      </div>
      <div className="bar"><div style={{ width: `${Math.max(1, value * 100)}%`, background: color, boxShadow: `0 0 8px ${color}` }} /></div>
    </div>
  );
}

export function StatTile({ value, label, color }: { value: ReactNode; label: string; color: string }) {
  return (
    <div className="glass stat">
      <div className="value" style={{ color }}>{value}</div>
      <div className="muted small" style={{ marginTop: 6 }}>{label}</div>
    </div>
  );
}

export function ConfidenceRing({ value, color, size = 84 }: { value: number; color: string; size?: number }) {
  const r = size / 2 - 5, c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} style={{ flex: "none" }}>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--hair)" strokeWidth="6" />
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth="6" strokeLinecap="round"
        strokeDasharray={`${c * value} ${c}`} transform={`rotate(-90 ${size / 2} ${size / 2})`}
        style={{ transition: "stroke-dasharray 0.6s ease", filter: `drop-shadow(0 0 5px ${color})` }} />
      <text x="50%" y="48%" textAnchor="middle" dominantBaseline="middle" fill="var(--ink)"
        style={{ fontFamily: "var(--serif)", fontStyle: "italic", fontSize: size * 0.32 }}>{Math.round(value * 100)}</text>
      <text x="50%" y="74%" textAnchor="middle" fill="var(--muted)" fontSize="10">%</text>
    </svg>
  );
}

/** Radar de l'empreinte olfactive (écart relatif à l'air propre, par capteur). */
export function Radar({ fingerprint, color, size = 260, labels = true }: { fingerprint: Record<string, number>; color: string; size?: number; labels?: boolean }) {
  const n = CHANNELS.length, cx = size / 2, cy = size / 2, R = size / 2 * (labels ? 0.68 : 0.9);
  const raw = CHANNELS.map((c) => Math.abs(fingerprint[c.key] ?? 0));
  const max = Math.max(...raw, 0.4);
  const vals = raw.map((v) => Math.min(v / max, 1));
  const pt = (i: number, v: number) => {
    const a = (i / n) * 2 * Math.PI - Math.PI / 2;
    return [cx + Math.cos(a) * v * R, cy + Math.sin(a) * v * R];
  };
  const poly = (vs: number[]) => vs.map((v, i) => pt(i, Math.max(v, 0.02)).join(",")).join(" ");
  return (
    <svg viewBox={`0 0 ${size} ${size}`} width="100%" style={{ maxWidth: size, display: "block", margin: "0 auto" }}>
      {[1, 2, 3].map((k) => <polygon key={k} points={poly(Array(n).fill(k / 3))} fill="none" stroke="var(--hair)" />)}
      {CHANNELS.map((_, i) => { const [x, y] = pt(i, 1); return <line key={i} x1={cx} y1={cy} x2={x} y2={y} stroke="var(--hair)" />; })}
      <polygon points={poly(vals)} fill={`${color}40`} stroke={color} strokeWidth="1.8"
        style={{ filter: `drop-shadow(0 0 6px ${color})`, transition: "all 0.6s ease" }} />
      {labels && CHANNELS.map((c, i) => {
        const [x, y] = pt(i, 1.24);
        return <text key={c.key} x={x} y={y} textAnchor="middle" dominantBaseline="middle" fill="var(--muted)" fontSize="11">{c.label}</text>;
      })}
    </svg>
  );
}

export function Empty({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="glass empty">
      <div className="display" style={{ fontSize: 26, marginBottom: 8 }}>{title}</div>
      <div className="muted">{children}</div>
    </div>
  );
}

export function DevicePicker() {
  const s = useStore();
  if (!s.devices.length) return null;
  return (
    <div className="field" style={{ padding: "0 12px", borderRadius: 999 }}>
      <GlowDot color={s.selected?.online ? "var(--mint)" : "var(--muted)"} size={7} />
      <select className="input" style={{ padding: "9px 0", cursor: "pointer" }} value={s.selected?.id ?? ""}
        onChange={(e) => s.selectDevice(e.target.value)}>
        {s.devices.map((d) => <option key={d.id} value={d.id}>{d.name}{d.room ? ` · ${d.room}` : ""}</option>)}
      </select>
    </div>
  );
}

export function Modal({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  return (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal">{children}</div>
    </div>
  );
}
