import { useEffect, useState } from "react";
import { DevicePicker, GlowBackground, Kicker, OdorIcon, PageHeader, accent } from "../components/ui";
import { useStore } from "../store";
import { OdorEditor } from "./Library";

const STEPS = [
  ["Air propre", "Laissez le nez à l'air libre ~10 s : il se calibre tout seul."],
  ["Présenter l'odeur", "Approchez l'odeur (café, fruit…) à 5 cm de la chambre de mesure."],
  ["Enregistrer", "Chaque fenêtre de 10 mesures devient un échantillon étiqueté."],
  ["Entraîner", "Avec au moins 2 odeurs (dont « Air ambiant »), entraînez le modèle."],
];

export default function Learn() {
  const s = useStore();
  const [odorId, setOdorId] = useState<number | null>(null);
  const [windows, setWindows] = useState(12);
  const [creating, setCreating] = useState(false);
  const [training, setTraining] = useState(false);
  const [trainError, setTrainError] = useState<string | null>(null);

  useEffect(() => { if (odorId === null && s.odors.length) setOdorId(s.odors[0].id); }, [s.odors, odorId]);

  const session = s.session;
  const sOdor = s.odor(session?.odor_id);
  const sColor = sOdor?.color ?? "var(--rose)";
  const meta = s.model?.meta ?? {};

  return (
    <>
      <GlowBackground colors={["var(--lilac)", "var(--rose)", "var(--gold)"]} />
      <PageHeader kicker="Mode apprentissage" title="Apprendre" color="var(--lilac)"><DevicePicker /></PageHeader>

      <div className="grid grid-2">
        <div className="stack">
          <div className="glass stack" style={{ gap: 14 }}>
            <Kicker>Protocole</Kicker>
            {STEPS.map(([t, d], i) => (
              <div key={t} className="row" style={{ alignItems: "flex-start", gap: 14 }}>
                <span className="display" style={{ fontSize: 24, color: "var(--lilac)", width: 20 }}>{i + 1}</span>
                <div><div style={{ fontWeight: 600 }}>{t}</div><div className="muted small">{d}</div></div>
              </div>
            ))}
          </div>

          {session?.status === "active" ? (
            <div className="glass stack" style={{ gap: 16 }}>
              <Kicker color={sColor}>Enregistrement en cours</Kicker>
              <div className="row" style={{ gap: 16 }}>
                <OdorIcon icon={sOdor?.icon ?? "👃"} color={sColor} size={66} />
                <div>
                  <div className="display" style={{ fontSize: 30 }}>{sOdor?.name}</div>
                  <div className="muted small">{session.collected === 0 ? "Montée de l'odeur… présentez-la maintenant" : `${session.collected} / ${session.target_windows} échantillons`}</div>
                </div>
              </div>
              <div className="bar" style={{ height: 10 }}><div style={{ width: `${(session.collected / session.target_windows) * 100}%`, background: sColor }} /></div>
              <div><button className="ghost" style={accent("var(--ember)")} onClick={s.cancelTraining}>Annuler</button></div>
            </div>
          ) : (
            <div className="glass stack" style={{ gap: 14 }}>
              <Kicker color="var(--rose)">Enregistrer une odeur</Kicker>
              <div className="row">
                <select className="input-box" value={odorId ?? ""} onChange={(e) => setOdorId(Number(e.target.value))}>
                  {s.odors.map((o) => <option key={o.id} value={o.id}>{o.icon}  {o.name}  ({o.samples})</option>)}
                </select>
                <button className="icon-btn" title="Nouvelle odeur" onClick={() => setCreating(true)}>+</button>
              </div>
              <div>
                <label className="lbl">{windows} échantillons · ≈ {windows * 5 + 20} s de mesure</label>
                <input type="range" min={3} max={40} value={windows} onChange={(e) => setWindows(Number(e.target.value))} style={{ width: "100%", accentColor: "var(--rose)" }} />
              </div>
              {s.selected && !s.selected.calibrated && <div className="error">Appareil pas encore calibré : patientez quelques secondes.</div>}
              {session?.status === "done" && (
                <div className="small" style={{ color: "var(--mint)" }}>✓ {sOdor?.name} enregistrée ({session.collected} échantillons). Pensez à réentraîner le modèle.</div>
              )}
              <button className="btn" disabled={!odorId || !s.selected}
                onClick={() => s.selected && odorId && s.startTraining(s.selected.id, odorId, windows)}>
                Démarrer l'enregistrement
              </button>
            </div>
          )}
        </div>

        {/* Modèle */}
        <div className="glass stack" style={{ gap: 16 }}>
          <div className="row between">
            <Kicker color="var(--mint)">Modèle Random Forest</Kicker>
            <span className="muted small">{s.model?.trained ? "entraîné" : "non entraîné"}</span>
          </div>
          {meta.accuracy !== undefined && (
            <div className="row" style={{ alignItems: "baseline", gap: 12 }}>
              <span className="display" style={{ fontSize: 30, color: "var(--mint)", lineHeight: 1 }}>{Math.round(meta.accuracy * 100)} %</span>
              <span className="muted small">de précision<br />(validation croisée, {meta.n_samples} échantillons)</span>
            </div>
          )}
          <div className="stack" style={{ gap: 6 }}>
            <div style={{ fontWeight: 600, fontSize: 14 }}>Échantillons par odeur</div>
            {s.odors.map((o) => {
              const n = s.model?.samples_per_odor[String(o.id)] ?? o.samples;
              return (
                <div key={o.id} className="row between small">
                  <span>{o.icon} {o.name}</span>
                  <span style={{ color: n >= 3 ? "var(--mint)" : "var(--muted)", fontVariantNumeric: "tabular-nums" }}>{n}</span>
                </div>
              );
            })}
          </div>

          {meta.confusion_matrix && meta.classes && (
            <div className="scroll-x">
              <div style={{ fontWeight: 600, fontSize: 14 }}>Matrice de confusion</div>
              <div className="muted small" style={{ marginBottom: 6 }}>Ligne = odeur réelle, colonne = odeur prédite</div>
              <table className="matrix">
                <tbody>
                  <tr><td />{meta.classes.map((k) => <td key={k.odor_id} title={k.name}>{s.odor(k.odor_id)?.icon ?? "?"}</td>)}</tr>
                  {meta.confusion_matrix.map((row, i) => {
                    const max = Math.max(...meta.confusion_matrix!.flat(), 1);
                    return (
                      <tr key={i}>
                        <td title={meta.classes![i].name}>{s.odor(meta.classes![i].odor_id)?.icon ?? "?"}</td>
                        {row.map((v, j) => (
                          <td key={j} style={{
                            background: `color-mix(in srgb, ${i === j ? "var(--mint)" : "var(--ember)"} ${v ? 15 + 60 * (v / max) : 4}%, transparent)`,
                            color: v ? "var(--ink)" : "rgba(167,159,181,0.5)",
                          }}>{v}</td>
                        ))}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {meta.top_features && (
            <div className="stack" style={{ gap: 6 }}>
              <div style={{ fontWeight: 600, fontSize: 14 }}>Caractéristiques les plus utiles</div>
              {meta.top_features.slice(0, 5).map((f) => (
                <div key={f.feature} className="row small" style={{ gap: 10 }}>
                  <span style={{ width: 130 }} className="muted">{f.feature}</span>
                  <div className="bar" style={{ flex: 1 }}><div style={{ width: `${f.importance * 100 / meta.top_features![0].importance}%`, background: "var(--mint)" }} /></div>
                </div>
              ))}
            </div>
          )}

          {trainError && <div className="error">{trainError}</div>}
          <button className="btn" style={accent("var(--mint)")} disabled={training}
            onClick={async () => { setTraining(true); setTrainError(await s.trainModel()); setTraining(false); }}>
            {training ? "Entraînement…" : "Entraîner le modèle"}
          </button>
        </div>
      </div>
      {creating && <OdorEditor onClose={() => setCreating(false)} />}
    </>
  );
}
