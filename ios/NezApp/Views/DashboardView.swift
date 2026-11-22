import Charts
import SwiftUI

/// Écran principal : ce que le nez sent en ce moment.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var showSettings = false

    private var device: Device? { store.selectedDevice }
    private var prediction: Prediction? { device.flatMap { store.predictions[$0.id] } }
    private var points: [ReadingPoint] { device.flatMap { store.readings[$0.id] } ?? [] }
    private var color: Color { Color(hex: prediction?.color ?? "#8E8E93") }

    var body: some View {
        NavigationStack {
            Group {
                if store.devices.isEmpty {
                    ContentUnavailableView("Aucun appareil", systemImage: "sensor",
                                           description: Text("Branchez le nez électronique ou lancez le simulateur sur l'ordinateur."))
                } else {
                    List {
                        nowSection
                        if let p = prediction, !p.probabilities.isEmpty { probabilitiesSection(p) }
                        sensorsSection
                        todaySection
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await store.refreshAll() }
                }
            }
            .navigationTitle("Le nez")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DevicePicker() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: - En ce moment

    private var nowSection: some View {
        Section {
            HStack(spacing: 14) {
                OdorIcon(icon: prediction?.icon ?? "👃", color: color, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    if let device, store.warming[device.id] == true {
                        Text("Préchauffage…").font(.title2.bold())
                        Text("Les capteurs chauffent, patientez quelques minutes.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if let p = prediction {
                        Text(p.label).font(.title2.bold())
                        Text("Mis à jour \(p.ts.relative)").font(.subheadline).foregroundStyle(.secondary)
                        if p.alertLevel != "none" { LevelBadge(level: p.alertLevel) }
                    } else {
                        Text("Analyse en cours").font(.title2.bold())
                        Text(device?.calibrated == true ? "Le nez analyse l'air…" : "Calibration à l'air propre…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let p = prediction, p.odorId != nil || p.confidence > 0 {
                    ConfidenceGauge(value: p.confidence, color: color)
                }
            }
            .padding(.vertical, 6)

            if let device {
                LabeledContent("Pièce", value: device.room ?? "Non définie")
                if let last = points.last {
                    LabeledContent("Température", value: String(format: "%.1f °C", last.data["temp"] ?? 0))
                    LabeledContent("Humidité", value: String(format: "%.0f %%", last.data["hum"] ?? 0))
                }
                HStack {
                    Text("Connexion")
                    Spacer()
                    Group {
                        Image(systemName: store.liveConnected ? "dot.radiowaves.left.and.right" : "wifi.slash")
                        Text(store.liveConnected ? "En direct" : "Hors ligne")
                    }
                    .foregroundStyle(store.liveConnected ? Color.green : Color.secondary)
                }
            }
        } header: {
            Text("En ce moment")
        } footer: {
            Text("Le pourcentage indique à quel point le nez est sûr de reconnaître cette odeur.")
        }
    }

    private func probabilitiesSection(_ p: Prediction) -> some View {
        Section {
            ForEach(p.probabilities.prefix(4), id: \.odorId) { item in
                ProbabilityRow(label: item.label, value: item.p, color: Color(hex: item.color))
            }
            NavigationLink {
                FingerprintView(fingerprint: p.fingerprint, color: color, title: p.label)
            } label: {
                Label("Voir l'empreinte olfactive", systemImage: "hexagon")
            }
        } header: {
            Text("Odeurs possibles")
        } footer: {
            Text("Les odeurs que le modèle hésite entre elles, de la plus probable à la moins probable.")
        }
    }

    // MARK: - Capteurs

    private var sensorsSection: some View {
        Section {
            ForEach(Channel.allCases) { ch in
                NavigationLink {
                    SensorChartView(channel: ch)
                } label: {
                    LabeledContent(ch.label) {
                        if let v = points.last?.data[ch.rawValue] {
                            Text("\(formatValue(v)) \(ch.unit)").monospacedDigit()
                        } else {
                            Text("—")
                        }
                    }
                }
            }
        } header: {
            Text("Capteurs")
        } footer: {
            Text("Touchez un capteur pour voir sa courbe en direct.")
        }
    }

    private var todaySection: some View {
        Section("Aujourd'hui") {
            LabeledContent("Odeurs détectées (24 h)", value: "\(store.stats?.detectionsDay ?? 0)")
            LabeledContent("Alertes non lues", value: "\(store.unreadAlerts)")
            LabeledContent("Appareils en ligne", value: "\(store.devices.filter(\.online).count) sur \(store.devices.count)")
        }
    }
}

/// Courbe en direct d'un capteur.
struct SensorChartView: View {
    @Environment(AppStore.self) private var store
    let channel: Channel

    private var series: [(Date, Double)] {
        let points = store.selectedDevice.flatMap { store.readings[$0.id] } ?? []
        return points.compactMap { p in p.data[channel.rawValue].map { (p.ts, $0) } }
    }

    var body: some View {
        List {
            Section {
                if series.count < 2 {
                    Text("Pas encore assez de mesures.").foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(series.indices, id: \.self) { i in
                            LineMark(x: .value("Heure", series[i].0), y: .value(channel.label, series[i].1))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.indigo)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 240)
                    .padding(.vertical, 8)
                }
            } footer: {
                Text("Les 3 dernières minutes environ, une mesure par seconde.")
            }
            if let last = series.last {
                Section {
                    LabeledContent("Valeur actuelle", value: "\(formatValue(last.1)) \(channel.unit)")
                    LabeledContent("Minimum", value: "\(formatValue(series.map(\.1).min() ?? 0)) \(channel.unit)")
                    LabeledContent("Maximum", value: "\(formatValue(series.map(\.1).max() ?? 0)) \(channel.unit)")
                }
            }
        }
        .navigationTitle(channel.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Empreinte olfactive : radar + valeurs.
struct FingerprintView: View {
    let fingerprint: [String: Double]
    let color: Color
    let title: String

    var body: some View {
        List {
            Section {
                RadarChart(fingerprint: fingerprint, color: color).frame(height: 260).padding(.vertical, 8)
            } footer: {
                Text("Chaque branche montre de combien un capteur réagit par rapport à l'air propre.")
            }
            Section("Écart par capteur") {
                ForEach(Channel.allCases) { ch in
                    LabeledContent(ch.label) {
                        Text(percentText(fingerprint[ch.rawValue] ?? 0))
                            .monospacedDigit()
                            .foregroundStyle(tint(fingerprint[ch.rawValue] ?? 0))
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func percentText(_ v: Double) -> String { String(format: "%+.0f %%", v * 100) }

    private func tint(_ v: Double) -> Color {
        if abs(v) < 0.05 { return .secondary }
        return v > 0 ? .orange : .blue
    }
}
