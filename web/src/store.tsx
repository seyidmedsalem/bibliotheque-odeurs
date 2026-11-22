import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  api, ApiError, getToken, setToken,
  type AlertItem, type Detection, type Device, type Health, type ModelInfo, type Odor, type OdorInput,
  type Prediction, type Reading, type Session, type Stats,
} from "./api";

const MAX_POINTS = 180;

/** État global : données du serveur + flux temps réel (WebSocket). */
function useNezStore() {
  const [token, setTok] = useState<string | null>(getToken());
  const [devices, setDevices] = useState<Device[]>([]);
  const [odors, setOdors] = useState<Odor[]>([]);
  const [alerts, setAlerts] = useState<AlertItem[]>([]);
  const [detections, setDetections] = useState<Detection[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [model, setModel] = useState<ModelInfo | null>(null);
  const [health, setHealth] = useState<Health | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(localStorage.getItem("nez-device"));
  const [predictions, setPredictions] = useState<Record<string, Prediction>>({});
  const [readings, setReadings] = useState<Record<string, Reading[]>>({});
  const [warming, setWarming] = useState<Record<string, boolean>>({});
  const [session, setSession] = useState<Session | null>(null);
  const [live, setLive] = useState(false);
  const [banner, setBanner] = useState<AlertItem | null>(null);
  const [error, setError] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const logout = useCallback(() => {
    setToken(null); setTok(null);
    wsRef.current?.close();
  }, []);

  const run = useCallback(async (fn: () => Promise<void>) => {
    try { await fn(); } catch (e) {
      if (e instanceof ApiError && e.status === 401) logout();
      setError((e as Error).message);
    }
  }, [logout]);

  const loadDevices = useCallback(() => run(async () => setDevices(await api<Device[]>("GET", "/api/devices"))), [run]);
  const loadOdors = useCallback(() => run(async () => setOdors(await api<Odor[]>("GET", "/api/odors"))), [run]);
  const loadAlerts = useCallback(() => run(async () => setAlerts(await api<AlertItem[]>("GET", "/api/alerts"))), [run]);
  const loadStats = useCallback(() => run(async () => setStats(await api<Stats>("GET", "/api/stats"))), [run]);
  const loadModel = useCallback(() => run(async () => setModel(await api<ModelInfo>("GET", "/api/model"))), [run]);
  const loadHealth = useCallback(() => run(async () => setHealth(await api<Health>("GET", "/api/health"))), [run]);
  const loadDetections = useCallback((hours = 24 * 7) =>
    run(async () => setDetections(await api<Detection[]>("GET", "/api/detections", undefined, { hours, limit: 2000 }))), [run]);
  const loadHistory = useCallback((id: string) => run(async () => {
    const rows = await api<Reading[]>("GET", `/api/devices/${id}/measurements`, undefined, { minutes: 5 });
    setReadings((r) => ({ ...r, [id]: rows.slice(-MAX_POINTS) }));
  }), [run]);

  const refreshAll = useCallback(async () => {
    await Promise.all([loadDevices(), loadOdors(), loadAlerts(), loadStats(), loadModel(), loadHealth(), loadDetections()]);
  }, [loadDevices, loadOdors, loadAlerts, loadStats, loadModel, loadHealth, loadDetections]);

  // ---------------------------------------------------------------- temps réel
  useEffect(() => {
    if (!token) return;
    refreshAll();
    let stopped = false;
    let retry: number | undefined;
    const connect = () => {
      const proto = window.location.protocol === "https:" ? "wss" : "ws";
      const ws = new WebSocket(`${proto}://${window.location.host}/ws?token=${encodeURIComponent(token)}`);
      wsRef.current = ws;
      ws.onopen = () => setLive(true);
      ws.onclose = () => { setLive(false); if (!stopped) retry = window.setTimeout(connect, 3000); };
      ws.onmessage = (msg) => {
        const e = JSON.parse(msg.data);
        switch (e.type) {
          case "reading":
            setReadings((r) => ({ ...r, [e.device_id]: [...(r[e.device_id] ?? []), { ts: e.ts, data: e.data }].slice(-MAX_POINTS) }));
            setWarming((w) => (w[e.device_id] === e.warming ? w : { ...w, [e.device_id]: e.warming }));
            break;
          case "prediction": setPredictions((p) => ({ ...p, [e.device_id]: e })); break;
          case "detection": setDetections((d) => [e.detection, ...d]); loadStats(); break;
          case "alert": setAlerts((a) => [e.alert, ...a]); setBanner(e.alert); break;
          case "training_progress":
            setSession(e.session);
            if (e.session.status !== "active") { loadOdors(); loadModel(); }
            break;
          case "device":
            setDevices((ds) => ds.some((d) => d.id === e.device.id) ? ds.map((d) => d.id === e.device.id ? e.device : d) : [...ds, e.device]);
            break;
          case "calibrated": loadDevices(); break;
        }
      };
    };
    connect();
    const ping = window.setInterval(() => wsRef.current?.readyState === 1 && wsRef.current.send("ping"), 20000);
    return () => { stopped = true; window.clearTimeout(retry); window.clearInterval(ping); wsRef.current?.close(); };
  }, [token, refreshAll, loadStats, loadOdors, loadModel, loadDevices]);

  useEffect(() => {
    if (!banner) return;
    const t = window.setTimeout(() => setBanner(null), 6000);
    return () => window.clearTimeout(t);
  }, [banner]);

  // Appareil sélectionné : celui choisi, sinon le premier en ligne
  const selected = useMemo(
    () => devices.find((d) => d.id === selectedId) ?? devices.find((d) => d.online) ?? devices[0] ?? null,
    [devices, selectedId],
  );
  useEffect(() => { if (selected && !readings[selected.id]) loadHistory(selected.id); }, [selected, readings, loadHistory]);

  const selectDevice = (id: string) => { setSelectedId(id); localStorage.setItem("nez-device", id); };

  // ---------------------------------------------------------------- actions
  const login = async (email: string, password: string) => {
    const r = await api<{ access_token: string }>("POST", "/api/auth/login", { email, password });
    setToken(r.access_token); setTok(r.access_token);
  };
  const upsertDevice = (d: Device) => setDevices((ds) => ds.map((x) => (x.id === d.id ? d : x)));
  const updateDevice = (id: string, body: Partial<Device> & { move_history?: boolean }) => run(async () => {
    upsertDevice(await api<Device>("PATCH", `/api/devices/${id}`, body));
    if (body.move_history) await loadDetections();
  });
  const calibrate = (id: string) => run(async () => { await api("POST", `/api/devices/${id}/calibrate`); });
  const identify = (id: string) => run(async () => { await api("POST", `/api/devices/${id}/identify`); });
  const saveOdor = async (input: OdorInput, id?: number) => {
    try {
      await api(id ? "PATCH" : "POST", id ? `/api/odors/${id}` : "/api/odors", input);
      await loadOdors();
      return true;
    } catch (e) { setError((e as Error).message); return false; }
  };
  const deleteOdor = (id: number) => run(async () => { await api("DELETE", `/api/odors/${id}`); await loadOdors(); });
  const startTraining = (device_id: string, odor_id: number, windows: number) => run(async () => {
    setSession(await api<Session>("POST", "/api/training/sessions", { device_id, odor_id, windows, skip_windows: 2 }));
  });
  const cancelTraining = () => run(async () => {
    if (session) setSession(await api<Session>("POST", `/api/training/sessions/${session.id}/cancel`));
  });
  const trainModel = async (): Promise<string | null> => {
    try { setModel(await api<ModelInfo>("POST", "/api/model/train")); return null; } catch (e) { return (e as Error).message; }
  };
  const acknowledge = (id: number) => run(async () => {
    const a = await api<AlertItem>("POST", `/api/alerts/${id}/ack`);
    setAlerts((as) => as.map((x) => (x.id === a.id ? a : x)));
  });
  const acknowledgeAll = () => run(async () => { await api("POST", "/api/alerts/ack-all"); await loadAlerts(); });

  return {
    token, devices, odors, alerts, detections, stats, model, health, predictions, readings, warming, session, live,
    banner, error, selected,
    odor: (id: number | null | undefined) => odors.find((o) => o.id === id),
    unread: alerts.filter((a) => !a.acknowledged).length,
    setBanner, setError, selectDevice, login, logout, refreshAll, loadDetections, loadHealth, loadModel, loadOdors,
    updateDevice, calibrate, identify, saveOdor, deleteOdor, startTraining, cancelTraining, trainModel,
    acknowledge, acknowledgeAll,
  };
}

export type NezStore = ReturnType<typeof useNezStore>;
const Ctx = createContext<NezStore | null>(null);

export function StoreProvider({ children }: { children: ReactNode }) {
  const store = useNezStore();
  return <Ctx.Provider value={store}>{children}</Ctx.Provider>;
}

export function useStore(): NezStore {
  const s = useContext(Ctx);
  if (!s) throw new Error("StoreProvider manquant");
  return s;
}
