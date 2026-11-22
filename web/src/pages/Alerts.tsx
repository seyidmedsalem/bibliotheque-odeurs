import { useState } from "react";
import { LEVELS, relative } from "../api";
import { Empty, GlowBackground, LevelBadge, PageHeader } from "../components/ui";
import { useStore } from "../store";

export default function Alerts() {
  const s = useStore();
  const [onlyUnread, setOnlyUnread] = useState(false);
  const items = onlyUnread ? s.alerts.filter((a) => !a.acknowledged) : s.alerts;

  return (
    <>
      <GlowBackground colors={["#FF8A5B", "#F27BA0", "#A98BFF"]} />
      <PageHeader kicker={`${s.unread} non lues`} title="Alertes" color="var(--ember)">
        <button className={`chip${!onlyUnread ? " active" : ""}`} onClick={() => setOnlyUnread(false)}>Toutes</button>
        <button className={`chip${onlyUnread ? " active" : ""}`} onClick={() => setOnlyUnread(true)}>Non lues</button>
        {s.unread > 0 && <button className="ghost" onClick={s.acknowledgeAll}>Tout marquer comme lu</button>}
      </PageHeader>

      <div className="stack" style={{ gap: 12, maxWidth: 820 }}>
        {!items.length && <Empty title="Rien à signaler">Les fuites de gaz, aliments qui se gâtent et odeurs suspectes apparaîtront ici.</Empty>}
        {items.map((a) => {
          const color = LEVELS[a.level]?.color ?? "var(--gold)";
          return (
            <div key={a.id} className="glass row" style={{ alignItems: "stretch", gap: 16, opacity: a.acknowledged ? 0.55 : 1 }}>
              <div style={{ width: 4, borderRadius: 2, background: color, boxShadow: `0 0 8px ${color}` }} />
              <div style={{ flex: 1 }} className="stack">
                <div className="row between" style={{ marginBottom: -10 }}>
                  <LevelBadge level={a.level} /><span className="muted small">{relative(a.ts)}</span>
                </div>
                <div style={{ fontWeight: 600, fontSize: 16 }}>{a.title}</div>
                <div className="muted" style={{ marginTop: -10 }}>{a.message}</div>
                {!a.acknowledged && (
                  <div><button className="ghost" style={{ padding: "5px 12px", fontSize: 12.5 }} onClick={() => s.acknowledge(a.id)}>Marquer comme lue</button></div>
                )}
              </div>
            </div>
          );
        })}
        <div className="muted small">⚠️ Ce système ne remplace pas un détecteur de gaz ou de CO certifié.</div>
      </div>
    </>
  );
}
