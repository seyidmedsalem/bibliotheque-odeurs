import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var channel: Channel = .sgp41Voc
    @State private var showSettings = false

    private var device: Device? { store.selectedDevice }
    private var prediction: Prediction? { device.flatMap { store.predictions[$0.id] } }
    private var points: [ReadingPoint] { device.flatMap { store.readings[$0.id] } ?? [] }
    private var color: Color { Color(hex: prediction?.color ?? "#A79FB5") }

    var body: some View {
        NavigationStack {
            ZStack {
                GlowBackground(colors: [color, Theme.lilac, Theme.mint])
                    .animation(.easeInOut(duration: 1.2), value: prediction?.color)
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .bottom) {
                            PageHeader(kicker: "En direct", title: "Le nez", color: Theme.mint)
                            VStack(alignment: .trailing, spacing: 10) {
                                Button { showSettings = true } label: {
                                    Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(Theme.ink)
                                }
                                DevicePicker()
                            }
                        }

                        if store.devices.isEmpty {
                            EmptyState(icon: "sensor", title: "Aucun appareil",
                                       message: "Branchez l'ESP32 ou lancez le simulateur :\npython simulate.py live")
                        } else {
                            heroCard
                            statsRow
                            if let prediction, !prediction.probabilities.isEmpty { probabilities(prediction) }
                            fingerprintCard
                            chartCard
                        }
                    }
                    .padding(20)
                }
                .refreshable { await store.refreshAll() }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: - Odeur reconnue

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Kicker("Odeur reconnue", color: color)
                Spacer()
                HStack(spacing: 6) {
                    GlowDot(color: store.liveConnected ? Theme.mint : Theme.ember, size: 6)
                    Text(store.liveConnected ? "temps réel" : "hors ligne").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 18) {
                OdorIcon(icon: prediction?.icon ?? "👃", color: color, size: 74)
                VStack(alignment: .leading, spacing: 6) {
                    if let device, store.warming[device.id] == true {
                        Text("Chauffe des capteurs…").font(.display(26)).foregroundStyle(Theme.ink)
                        Text("Les mesures seront fiables dans quelques minutes.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    } else {
                        Text(prediction?.label ?? "En attente…").font(.display(30)).foregroundStyle(Theme.ink)
                            .minimumScaleFactor(0.6).lineLimit(2)
                        if let prediction {
                            HStack(spacing: 8) {
                                if prediction.alertLevel != "none" { LevelBadge(level: prediction.alertLevel) }
                                Text(prediction.ts.relative).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        } else {
                            Text(device?.calibrated == true ? "Analyse de l'air en cours" : "Calibration à l'air propre…")
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let prediction, prediction.odorId != nil || prediction.confidence > 0 {
                    ConfidenceRing(value: prediction.confidence, color: color).frame(width: 66, height: 66)
                }
            }
            if let device {
                HStack(spacing: 14) {
                    Label(device.room ?? "Pièce non définie", systemImage: "house").font(.system(size: 12))
                    if let last = points.last {
                        Label(String(format: "%.1f °C", last.data["temp"] ?? 0), systemImage: "thermometer.medium").font(.system(size: 12))
                        Label(String(format: "%.0f %%", last.data["hum"] ?? 0), systemImage: "humidity").font(.system(size: 12))
                    }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .glass(padding: 18)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(store.stats?.detectionsDay ?? 0)", label: "détections\nsur 24 h", color: Theme.gold)
            StatTile(value: "\(store.unreadAlerts)", label: "alertes\nnon lues", color: store.unreadAlerts > 0 ? Theme.ember : Theme.mint)
            StatTile(value: "\(store.devices.filter(\.online).count)/\(store.devices.count)", label: "appareils\nen ligne", color: Theme.sky)
        }
    }

    private func probabilities(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Probabilités", color: Theme.lilac)
            ForEach(p.probabilities.prefix(4), id: \.odorId) { item in
                ProbabilityBar(label: item.label, value: item.p, color: Color(hex: item.color))
            }
        }
        .glass(padding: 18)
    }

    private var fingerprintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Empreinte olfactive", color: Theme.gold)
            Text("Écart de chaque capteur par rapport à l'air propre").font(.system(size: 12)).foregroundStyle(Theme.muted)
            RadarChart(fingerprint: prediction?.fingerprint ?? [:], color: color).frame(height: 240)
        }
        .glass(padding: 18)
    }

    // MARK: - Courbe en direct

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker("Capteur en direct", color: Theme.sky)
                Spacer()
                if let v = points.last?.data[channel.rawValue] {
                    Text(format(v) + " " + channel.unit).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ink)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Channel.allCases) { ch in
                        Button(ch.label) { channel = ch }
                            .buttonStyle(GhostButtonStyle(color: ch == channel ? Theme.sky : Theme.muted))
                    }
                }
            }
            let series = points.compactMap { p in p.data[channel.rawValue].map { (p.ts, $0) } }
            if series.count < 2 {
                Text("Pas encore de mesures pour ce capteur.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(series.indices, id: \.self) { i in
                        AreaMark(x: .value("Heure", series[i].0), y: .value(channel.label, series[i].1))
                            .foregroundStyle(LinearGradient(colors: [Theme.sky.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Heure", series[i].0), y: .value(channel.label, series[i].1))
                            .foregroundStyle(Theme.sky)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour().minute().second()) } }
                .frame(height: 180)
            }
        }
        .glass(padding: 18)
    }

    private func format(_ v: Double) -> String {
        abs(v) >= 1000 ? String(format: "%.0f", v) : abs(v) >= 10 ? String(format: "%.1f", v) : String(format: "%.3f", v)
    }
}
