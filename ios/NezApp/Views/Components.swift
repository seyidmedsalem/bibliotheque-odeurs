import SwiftUI

/// Graphique radar de l'empreinte olfactive (écart relatif à l'air propre, par capteur).
struct RadarChart: View {
    var fingerprint: [String: Double]
    var color: Color
    var showLabels = true
    var channels: [Channel] = Channel.allCases

    private var values: [Double] {
        let raw = channels.map { abs(fingerprint[$0.rawValue] ?? 0) }
        let maxV = max(raw.max() ?? 0, 0.4)
        return raw.map { min($0 / maxV, 1) }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 * (showLabels ? 0.72 : 0.92)
            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    polygon(Array(repeating: Double(ring) / 3, count: channels.count), center: center, radius: radius)
                        .stroke(Theme.hair, lineWidth: 0.7)
                }
                ForEach(channels.indices, id: \.self) { i in
                    Path { p in p.move(to: center); p.addLine(to: point(i, 1, center, radius)) }
                        .stroke(Theme.hair, lineWidth: 0.7)
                }
                polygon(values, center: center, radius: radius).fill(color.opacity(0.25))
                polygon(values, center: center, radius: radius).stroke(color, lineWidth: 1.6)
                    .shadow(color: color.opacity(0.8), radius: 6)
                if showLabels {
                    ForEach(channels.indices, id: \.self) { i in
                        Text(channels[i].label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .position(point(i, 1.22, center, radius))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: values)
    }

    private func point(_ i: Int, _ v: Double, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let angle = Double(i) / Double(channels.count) * 2 * .pi - .pi / 2
        return CGPoint(x: c.x + CGFloat(cos(angle) * v) * r, y: c.y + CGFloat(sin(angle) * v) * r)
    }

    private func polygon(_ vals: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for (i, v) in vals.enumerated() {
                let pt = point(i, max(v, 0.02), center, radius)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
    }
}

/// Anneau de confiance.
struct ConfidenceRing: View {
    var value: Double
    var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Theme.hair, lineWidth: 6)
            Circle().trim(from: 0, to: value).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90)).shadow(color: color, radius: 6)
            VStack(spacing: 0) {
                Text("\(Int(value * 100))").font(.display(26)).foregroundStyle(Theme.ink)
                Text("%").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .animation(.easeInOut, value: value)
    }
}

/// Barre de probabilité pour une odeur.
struct ProbabilityBar: View {
    var label: String
    var value: Double
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(value * 100)) %").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color).frame(width: max(4, geo.size.width * value)).shadow(color: color.opacity(0.7), radius: 4)
                }
            }
            .frame(height: 6)
        }
        .animation(.easeInOut, value: value)
    }
}

/// Tuile de chiffre clé.
struct StatTile: View {
    var value: String
    var label: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.display(30)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(padding: 14)
    }
}

/// Emoji de l'odeur dans un halo coloré.
struct OdorIcon: View {
    var icon: String
    var color: Color
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: size, height: size)
                .shadow(color: color.opacity(0.7), radius: size * 0.35)
            Circle().stroke(color.opacity(0.7), lineWidth: 1).frame(width: size, height: size)
            Text(icon).font(.system(size: size * 0.48))
        }
    }
}

/// Pastille de niveau d'alerte.
struct LevelBadge: View {
    var level: String
    var body: some View {
        Text(Theme.levelName(level))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.level(level))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.level(level).opacity(0.14)))
    }
}

/// Message quand une liste est vide.
struct EmptyState: View {
    var icon: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.gold)
            Text(title).font(.display(22)).foregroundStyle(Theme.ink)
            Text(message).font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .glass()
    }
}

/// Sélecteur d'appareil (menu en capsule).
struct DevicePicker: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Menu {
            ForEach(store.devices) { d in
                Button {
                    store.selectedDeviceId = d.id
                    if store.readings[d.id] == nil { Task { await store.loadHistory(d.id) } }
                } label: {
                    Label(d.name + (d.room.map { " · \($0)" } ?? ""), systemImage: d.online ? "dot.radiowaves.left.and.right" : "moon.zzz")
                }
            }
        } label: {
            HStack(spacing: 8) {
                GlowDot(color: store.selectedDevice?.online == true ? Theme.mint : Theme.muted, size: 7)
                Text(store.selectedDevice?.name ?? "Aucun appareil").font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(Theme.hair))
        }
    }
}

extension Date {
    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
