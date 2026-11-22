// Client de l'API FastAPI. Même origine que la page (proxy Vite en dev, nginx en production).

export type Device = {
  id: string; name: string; room: string | null; lat: number | null; lon: number | null;
  state: string; last_seen: string | null; calibrated: boolean; online: boolean;
};
export type Odor = {
  id: number; name: string; icon: string; color: string; alert_level: string; description: string | null;
  is_air: boolean; samples: number; detections: number; fingerprint: Record<string, number>; last_detected: string | null;
};
export type OdorInput = { name: string; icon: string; color: string; alert_level: string; description: string | null };
export type Detection = {
  id: number; ts: string; device_id: string; odor_id: number | null; label: string; confidence: number;
  lat: number | null; lon: number | null; room: string | null;
};
export type AlertItem = {
  id: number; ts: string; device_id: string; level: string; title: string; message: string;
  odor_id: number | null; acknowledged: boolean;
};
export type Session = {
  id: number; device_id: string; odor_id: number; target_windows: number; skip_windows: number;
  collected: number; status: string; created_at: string;
};
export type ModelInfo = {
  trained: boolean;
  meta: {
    trained_at?: string; n_samples?: number; accuracy?: number; cv_folds?: number;
    classes?: { odor_id: number; name: string; samples: number }[];
    confusion_matrix?: number[][];
    top_features?: { feature: string; importance: number }[];
  };
  samples_per_odor: Record<string, number>;
};
export type Stats = {
  detections_day: number; detections_total: number; unacknowledged_alerts: number;
  devices_online: number; devices_total: number;
  by_odor: { odor_id: number | null; label: string; color: string; icon: string; count: number }[];
  by_room: { room: string; count: number }[];
  timeline: { hour: string; count: number }[];
};
export type Health = { status: string; mqtt_connected: boolean; model_trained: boolean };
export type Prediction = {
  device_id: string; odor_id: number | null; label: string; confidence: number; color: string; icon: string;
  alert_level: string; probabilities: { odor_id: number; label: string; color: string; p: number }[];
  fingerprint: Record<string, number>; ts: string;
};
export type Reading = { ts: string; data: Record<string, number> };

export const CHANNELS: { key: string; label: string; unit: string }[] = [
  { key: "bme688_gas", label: "BME688", unit: "Ω" },
  { key: "sgp41_voc", label: "COV", unit: "indice" },
  { key: "sgp41_nox", label: "NOx", unit: "indice" },
  { key: "ens160_tvoc", label: "COVT", unit: "ppb" },
  { key: "mq3", label: "Alcool", unit: "V" },
  { key: "mq4", label: "Méthane", unit: "V" },
  { key: "mq135", label: "Ammoniac", unit: "V" },
];

export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message); }
}

let token: string | null = localStorage.getItem("nez-token");
export const getToken = () => token;
export function setToken(t: string | null) {
  token = t;
  if (t) localStorage.setItem("nez-token", t); else localStorage.removeItem("nez-token");
}

export async function api<T>(method: string, path: string, body?: unknown, query?: Record<string, string | number | undefined>): Promise<T> {
  const url = new URL(path, window.location.origin);
  Object.entries(query ?? {}).forEach(([k, v]) => v !== undefined && url.searchParams.set(k, String(v)));
  let res: Response;
  try {
    res = await fetch(url, {
      method,
      headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError("Serveur injoignable. Le backend est-il lancé ?", 0);
  }
  if (!res.ok) {
    let msg = `Erreur ${res.status}`;
    try {
      const j = await res.json();
      msg = typeof j.detail === "string" ? j.detail : Array.isArray(j.detail) ? j.detail.map((d: { msg: string }) => d.msg).join("\n") : msg;
    } catch { /* corps vide */ }
    throw new ApiError(msg, res.status);
  }
  return res.status === 204 ? (undefined as T) : res.json();
}

/** Dates du serveur : ISO, parfois sans fuseau (SQLite) → considérées comme UTC. */
export function parseDate(s: string): Date {
  return new Date(/[zZ]|[+-]\d\d:\d\d$/.test(s) ? s : s + "Z");
}

export function relative(s: string | null): string {
  if (!s) return "jamais";
  const sec = Math.round((Date.now() - parseDate(s).getTime()) / 1000);
  const rtf = new Intl.RelativeTimeFormat("fr", { numeric: "auto", style: "short" });
  if (Math.abs(sec) < 60) return rtf.format(-sec, "second");
  if (Math.abs(sec) < 3600) return rtf.format(-Math.round(sec / 60), "minute");
  if (Math.abs(sec) < 86400) return rtf.format(-Math.round(sec / 3600), "hour");
  return rtf.format(-Math.round(sec / 86400), "day");
}

export const LEVELS: Record<string, { name: string; color: string }> = {
  none: { name: "Aucune", color: "#34C759" },
  info: { name: "Info", color: "#007AFF" },
  warning: { name: "Attention", color: "#FF9500" },
  danger: { name: "Danger", color: "#FF3B30" },
};
