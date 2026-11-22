import { useState, type FormEvent } from "react";
import { GlowBackground } from "../components/ui";
import { useStore } from "../store";

export default function Login() {
  const s = useStore();
  const [email, setEmail] = useState("admin@nez.local");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setLoading(true); setError(null);
    try { await s.login(email, password); } catch (err) { setError((err as Error).message); }
    setLoading(false);
  };

  return (
    <div style={{ minHeight: "100%", display: "grid", placeItems: "center", padding: 24 }}>
      <GlowBackground colors={["#F27BA0", "#A98BFF", "#6FE3C1"]} />
      <form onSubmit={submit} style={{ width: "min(440px, 100%)" }} className="stack">
        <div>
          <div className="kicker">Projet IoT · Nez électronique</div>
          <h1 className="display" style={{ fontSize: 58, lineHeight: 1, margin: "14px 0 14px", fontWeight: 400 }}>
            La bibliothèque<br />des odeurs
          </h1>
          <div style={{ width: 64, height: 1.5, background: "var(--gold)" }} />
          <p className="muted">Connectez-vous pour voir ce que sent votre maison.</p>
        </div>
        <div className="field"><span style={{ color: "var(--gold)" }}>✉</span>
          <input type="email" placeholder="E-mail" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" />
        </div>
        <div className="field"><span style={{ color: "var(--gold)" }}>⚿</span>
          <input type="password" placeholder="Mot de passe" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" autoFocus />
        </div>
        {error && <div className="error">{error}</div>}
        <button className="btn block" disabled={loading || !password}>{loading ? "Connexion…" : "Se connecter"}</button>
        <div className="display" style={{ textAlign: "center", color: "var(--gold)", fontSize: 18, marginTop: 20 }}>Seyid Cheikh</div>
      </form>
    </div>
  );
}
