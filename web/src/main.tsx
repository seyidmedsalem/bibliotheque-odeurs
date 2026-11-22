import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Navigate, NavLink, Route, Routes } from "react-router-dom";
import "leaflet/dist/leaflet.css";
import "./styles.css";
import { LEVELS } from "./api";
import { GlowDot } from "./components/ui";
import { StoreProvider, useStore } from "./store";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Learn from "./pages/Learn";
import Library from "./pages/Library";
import MapPage from "./pages/MapPage";
import Alerts from "./pages/Alerts";
import Devices from "./pages/Devices";

const NAV = [
  { to: "/", label: "Direct", icon: "〰" },
  { to: "/apprendre", label: "Apprendre", icon: "✦" },
  { to: "/bibliotheque", label: "Bibliothèque", icon: "❖" },
  { to: "/carte", label: "Carte", icon: "◎" },
  { to: "/alertes", label: "Alertes", icon: "◔" },
  { to: "/appareils", label: "Appareils", icon: "⚙" },
];

function Shell() {
  const s = useStore();
  if (!s.token) return <Login />;
  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand">
          <div className="kicker">Nez électronique</div>
          <div className="title" style={{ marginTop: 8 }}>La bibliothèque<br />des odeurs</div>
        </div>
        {NAV.map((n) => (
          <NavLink key={n.to} to={n.to} end className={({ isActive }) => `nav-link${isActive ? " active" : ""}`}>
            <span style={{ width: 18, textAlign: "center" }}>{n.icon}</span>
            {n.label}
            {n.to === "/alertes" && s.unread > 0 && <span className="badge">{s.unread}</span>}
          </NavLink>
        ))}
        <div className="foot">
          <div className="row" style={{ gap: 8, marginBottom: 8 }}>
            <GlowDot color={s.live ? "var(--mint)" : "var(--ember)"} size={7} />
            {s.live ? "Temps réel connecté" : "Hors ligne"}
          </div>
          <div className="display" style={{ fontSize: 16, color: "var(--gold)" }}>Seyid Cheikh</div>
        </div>
      </aside>
      <main className="main">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/apprendre" element={<Learn />} />
          <Route path="/bibliotheque" element={<Library />} />
          <Route path="/carte" element={<MapPage />} />
          <Route path="/alertes" element={<Alerts />} />
          <Route path="/appareils" element={<Devices />} />
          <Route path="*" element={<Navigate to="/" />} />
        </Routes>
      </main>
      {s.banner && (
        <div className="banner" onClick={() => s.setBanner(null)}
          style={{ border: `1px solid ${LEVELS[s.banner.level]?.color}`, boxShadow: `0 0 30px ${LEVELS[s.banner.level]?.color}66` }}>
          <GlowDot color={LEVELS[s.banner.level]?.color ?? "var(--gold)"} size={12} />
          <div>
            <div style={{ fontWeight: 600 }}>{s.banner.title}</div>
            <div className="muted small">{s.banner.message}</div>
          </div>
        </div>
      )}
      {s.error && (
        <div className="banner" onClick={() => s.setError(null)} style={{ border: "1px solid var(--ember)" }}>
          <div><div style={{ fontWeight: 600 }}>Erreur</div><div className="error">{s.error}</div></div>
        </div>
      )}
    </div>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <StoreProvider>
        <Shell />
      </StoreProvider>
    </BrowserRouter>
  </StrictMode>,
);
