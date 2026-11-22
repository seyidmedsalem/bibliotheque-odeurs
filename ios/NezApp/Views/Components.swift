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
            let radius = size / 2 * (showLabels ? 0.7 : 0.92)
            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    polygon(Array(repeating: Double(ring) / 3, count: channels.count), center: center, radius: radius)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.7)
                }
                polygon(values, center: center, radius: radius).fill(color.opacity(0.2))
                polygon(values, center: center, radius: radius).stroke(color, lineWidth: 2)
                if showLabels {
                    ForEach(channels.indices, id: \.self) { i in
                        Text(channels[i].label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .position(point(i, 1.22, center, radius))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: values)
        .accessibilityLabel("Empreinte olfactive")
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

/// Emoji de l'odeur sur un cercle teinté.
struct OdorIcon: View {
    var icon: String
    var color: Color
    var size: CGFloat = 40
    var body: some View {
        Text(icon)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.18)))
    }
}

/// Jauge circulaire de confiance (style Apple).
struct ConfidenceGauge: View {
    var value: Double
    var color: Color
    var body: some View {
        Gauge(value: value) {
            Text("Confiance")
        } currentValueLabel: {
            Text("\(Int(value * 100))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(color)
        .accessibilityValue("\(Int(value * 100)) pour cent")
    }
}

/// Pastille de niveau d'alerte.
struct LevelBadge: View {
    var level: String
    var body: some View {
        Label(Theme.levelName(level), systemImage: Theme.levelIcon(level))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.level(level))
            .labelStyle(.titleAndIcon)
    }
}

/// Barre de probabilité pour une odeur.
struct ProbabilityRow: View {
    var label: String
    var value: Double
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value).tint(color)
        }
        .padding(.vertical, 2)
    }
}

/// Sélecteur d'appareil (menu dans la barre d'outils).
struct DevicePicker: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Menu {
            ForEach(store.devices) { d in
                Button {
                    store.selectedDeviceId = d.id
                    if store.readings[d.id] == nil { Task { await store.loadHistory(d.id) } }
                } label: {
                    if d.id == store.selectedDevice?.id {
                        Label(d.name, systemImage: "checkmark")
                    } else {
                        Text(d.name + (d.room.map { " · \($0)" } ?? ""))
                    }
                }
            }
        } label: {
            Label(store.selectedDevice?.name ?? "Appareil", systemImage: "sensor")
        }
    }
}

extension Date {
    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}

func formatValue(_ v: Double) -> String {
    abs(v) >= 1000 ? String(format: "%.0f", v) : abs(v) >= 10 ? String(format: "%.1f", v) : String(format: "%.3f", v)
}
