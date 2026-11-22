import { useState } from "react";
import { CHANNELS, LEVELS, relative, type Odor } from "../api";
import { GlowBackground, Kicker, LevelBadge, Modal, OdorIcon, PageHeader, Radar, StatTile, accent } from "../components/ui";
import { useStore } from "../store";

export default function Library() {
  const s = useStore();
  const [openId, setOpenId] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);
  const open = s.odor(openId);

  return (
    <>
      <GlowBackground colors={["var(--gold)", "var(--rose)", "var(--lilac)"]} />
      <PageHeader kicker={`${s.odors.length} odeurs archivées`} title="Bibliothèque">
        <button className="btn" onClick={() => setCreating(true)}>+ Nouvelle odeur</button>
      </PageHeader>
      <div className="grid grid-cards">
        {s.odors.map((o) => (
          <button key={o.id} className="glass stack" style={{ gap: 10, textAlign: "left", cursor: "pointer" }} onClick={() => setOpenId(o.id)}>
            <div className="row between">
              <OdorIcon icon={o.icon} color={o.color} size={44} />
              {o.alert_level !== "none" && <LevelBadge level={o.alert_level} />}
            </div>
            <div className="display" style={{ fontSize: 26 }}>{o.name}</div>
            <Radar fingerprint={o.fingerprint} color={o.color} size={150} labels={false} />
            <div className="row between muted small">
              <span>◫ {o.samples} échantillons</span><span>◎ {o.detections}</span>
            </div>
          </button>
        ))}
      </div>
      {open && <OdorDetail odor={open} onClose={() => setOpenId(null)} />}
      {creating && <OdorEditor onClose={() => setCreating(false)} />}
    </>
  );
}

function OdorDetail({ odor, onClose }: { odor: Odor; onClose: () => void }) {
  const s = useStore();
  const [editing, setEditing] = useState(false);
  if (editing) return <OdorEditor odor={odor} onClose={() => setEditing(false)} />;
  return (
    <Modal onClose={onClose}>
      <div className="stack">
        <div className="row" style={{ gap: 16 }}>
          <OdorIcon icon={odor.icon} color={odor.color} size={72} />
          <div style={{ flex: 1 }}>
            <div className="display" style={{ fontSize: 30 }}>{odor.name}</div>
            <LevelBadge level={odor.alert_level} />
          </div>
          <button className="icon-btn" onClick={onClose}>×</button>
        </div>
        {odor.description && <div className="muted">{odor.description}</div>}
        <div className="grid grid-2" style={{ gridTemplateColumns: "1fr 1fr" }}>
          <StatTile value={odor.samples} label="échantillons d'apprentissage" color={odor.color} />
          <StatTile value={odor.detections} label="détections au total" color="var(--gold)" />
        </div>
        <div>
          <Kicker color={odor.color}>Empreinte moyenne</Kicker>
          {!Object.keys(odor.fingerprint).length && <div className="muted small">Pas encore d'échantillon : enregistrez cette odeur dans « Apprendre ».</div>}
          <Radar fingerprint={odor.fingerprint} color={odor.color} size={280} />
          {CHANNELS.filter((c) => Math.abs(odor.fingerprint[c.key] ?? 0) > 0.0001).map((c) => {
            const v = odor.fingerprint[c.key];
            return (
              <div key={c.key} className="row between small" style={{ padding: "3px 0" }}>
                <span>{c.label}</span>
                <span style={{ color: v >= 0 ? "var(--ember)" : "var(--sky)", fontVariantNumeric: "tabular-nums" }}>{v >= 0 ? "+" : ""}{(v * 100).toFixed(0)} %</span>
              </div>
            );
          })}
        </div>
        {odor.last_detected && <div className="muted small">Dernière détection {relative(odor.last_detected)}</div>}
        <div className="row">
          <button className="btn" style={accent(odor.color)} onClick={() => setEditing(true)}>Modifier</button>
          {!odor.is_air && (
            <button className="ghost" style={accent("var(--ember)")} onClick={() => {
              if (confirm(`Supprimer « ${odor.name} » et ses échantillons ?`)) { s.deleteOdor(odor.id); onClose(); }
            }}>Supprimer</button>
          )}
        </div>
      </div>
    </Modal>
  );
}

export function OdorEditor({ odor, onClose }: { odor?: Odor; onClose: () => void }) {
  const s = useStore();
  const [name, setName] = useState(odor?.name ?? "");
  const [icon, setIcon] = useState(odor?.icon ?? "👃");
  const [color, setColor] = useState(odor?.color ?? "var(--lilac)");
  const [level, setLevel] = useState(odor?.alert_level ?? "none");
  const [description, setDescription] = useState(odor?.description ?? "");
  const [saving, setSaving] = useState(false);

  const save = async () => {
    setSaving(true);
    const ok = await s.saveOdor({ name: name.trim(), icon: [...icon].slice(0, 2).join(""), color: color.toUpperCase(), alert_level: level, description: description || null }, odor?.id);
    setSaving(false);
    if (ok) onClose();
  };

  return (
    <Modal onClose={onClose}>
      <div className="stack">
        <div className="display" style={{ fontSize: 30 }}>{odor ? "Modifier l'odeur" : "Nouvelle odeur"}</div>
        <div className="row" style={{ alignItems: "flex-end" }}>
          <div style={{ width: 80 }}><label className="lbl">Emoji</label><input className="input-box" value={icon} onChange={(e) => setIcon(e.target.value)} style={{ textAlign: "center", fontSize: 20 }} /></div>
          <div style={{ flex: 1 }}><label className="lbl">Nom</label><input className="input-box" placeholder="ex. Lavande" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></div>
          <div><label className="lbl">Couleur</label><input type="color" value={color} onChange={(e) => setColor(e.target.value)} style={{ width: 50, height: 42, border: "none", background: "none", cursor: "pointer" }} /></div>
        </div>
        <div>
          <label className="lbl">Alerte quand elle est détectée</label>
          <div className="row wrap" style={{ gap: 6 }}>
            {Object.entries(LEVELS).map(([k, l]) => (
              <button key={k} className={`chip${level === k ? " active" : ""}`} style={accent(l.color)} onClick={() => setLevel(k)}>{l.name}</button>
            ))}
          </div>
        </div>
        <div><label className="lbl">Description</label><textarea className="input-box" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} /></div>
        <div className="row">
          <button className="btn" style={accent(color)} disabled={!name.trim() || saving} onClick={save}>{saving ? "Enregistrement…" : "Enregistrer"}</button>
          <button className="ghost" onClick={onClose}>Annuler</button>
        </div>
      </div>
    </Modal>
  );
}
