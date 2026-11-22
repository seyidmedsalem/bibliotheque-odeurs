import SwiftUI

struct LearnView: View {
    @Environment(AppStore.self) private var store
    @State private var odorId: Int?
    @State private var windows = 12
    @State private var showEditor = false
    @State private var training = false
    @State private var trainError: String?

    private var session: TrainingSession? { store.activeSession }
    private var sessionOdor: Odor? { store.odor(session?.odorId) }

    var body: some View {
        NavigationStack {
            ZStack {
                GlowBackground(colors: [Theme.lilac, Theme.rose, Theme.gold])
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .bottom) {
                            PageHeader(kicker: "Mode apprentissage", title: "Apprendre", color: Theme.lilac)
                            DevicePicker()
                        }
                        stepsCard
                        if let session, session.status == "active" { progressCard(session) } else { recordCard }
                        if let session, session.status == "done" { doneCard(session) }
                        modelCard
                    }
                    .padding(20)
                }
                .refreshable { await store.loadModel(); await store.loadOdors() }
            }
            .sheet(isPresented: $showEditor) { OdorEditor(odor: nil) }
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Protocole", color: Theme.gold)
            step(1, "Air propre", "Laissez le nez à l'air libre ~10 s : il se calibre tout seul.")
            step(2, "Présenter l'odeur", "Approchez l'odeur (café, fruit…) à 5 cm de la chambre de mesure.")
            step(3, "Enregistrer", "Chaque fenêtre de 10 mesures devient un échantillon étiqueté.")
            step(4, "Entraîner", "Avec au moins 2 odeurs (dont « Air ambiant »), entraînez le modèle.")
        }
        .glass(padding: 18)
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.display(20)).foregroundStyle(Theme.lilac).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: - Enregistrement

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Enregistrer une odeur", color: Theme.rose)
            HStack {
                Menu {
                    ForEach(store.odors) { o in
                        Button("\(o.icon)  \(o.name)  (\(o.samples))") { odorId = o.id }
                    }
                } label: {
                    HStack {
                        if let o = store.odor(odorId) {
                            Text(o.icon)
                            Text(o.name).foregroundStyle(Theme.ink)
                        } else {
                            Text("Choisir une odeur").foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.muted)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                }
                Button { showEditor = true } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
            }
            Stepper(value: $windows, in: 3...40) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(windows) échantillons").foregroundStyle(Theme.ink)
                    Text("≈ \(windows * 5 + 20) s de mesure").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            if store.selectedDevice?.calibrated == false {
                Label("Appareil pas encore calibré : patientez quelques secondes.", systemImage: "hourglass")
                    .font(.system(size: 12)).foregroundStyle(Theme.ember)
            }
            Button("Démarrer l'enregistrement") {
                guard let device = store.selectedDevice, let odorId else { return }
                Task { await store.startTraining(deviceId: device.id, odorId: odorId, windows: windows) }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.rose))
            .disabled(odorId == nil || store.selectedDevice == nil)
            .opacity(odorId == nil ? 0.5 : 1)
        }
        .glass(padding: 18)
        .onAppear { if odorId == nil { odorId = store.odors.first?.id } }
    }

    private func progressCard(_ s: TrainingSession) -> some View {
        let color = Color(hex: sessionOdor?.color ?? "#F27BA0")
        return VStack(alignment: .leading, spacing: 16) {
            Kicker("Enregistrement en cours", color: color)
            HStack(spacing: 16) {
                OdorIcon(icon: sessionOdor?.icon ?? "👃", color: color, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionOdor?.name ?? "Odeur").font(.display(28)).foregroundStyle(Theme.ink)
                    Text(s.collected == 0 ? "Montée de l'odeur… présentez-la maintenant" : "\(s.collected) / \(s.targetWindows) échantillons")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            ProgressView(value: s.progress).tint(color).scaleEffect(x: 1, y: 2)
            Button("Annuler") { Task { await store.cancelTraining() } }.buttonStyle(GhostButtonStyle(color: Theme.ember))
        }
        .glass(padding: 18)
    }

    private func doneCard(_ s: TrainingSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(Theme.mint)
            VStack(alignment: .leading) {
                Text("\(sessionOdor?.name ?? "Odeur") enregistrée").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("\(s.collected) échantillons ajoutés. Pensez à réentraîner le modèle.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    // MARK: - Modèle

    private var modelCard: some View {
        let info = store.modelInfo
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Kicker("Modèle Random Forest", color: Theme.mint)
                Spacer()
                Text(info?.trained == true ? "entraîné" : "non entraîné").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if let acc = info?.meta.accuracy {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(acc * 100)) %").font(.display(48)).foregroundStyle(Theme.mint)
                    Text("de précision\n(validation croisée)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Text("\(info?.meta.nSamples ?? 0) échantillons · \(info?.meta.classes?.count ?? 0) odeurs")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Échantillons par odeur").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                ForEach(store.odors) { o in
                    let n = info?.samplesPerOdor[String(o.id)] ?? o.samples
                    HStack {
                        Text(o.icon)
                        Text(o.name).font(.system(size: 13)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(n)").font(.system(size: 13).monospacedDigit()).foregroundStyle(n >= 3 ? Theme.mint : Theme.muted)
                    }
                }
            }

            if let matrix = info?.meta.confusionMatrix, let classes = info?.meta.classes, !classes.isEmpty {
                ConfusionMatrixView(matrix: matrix, classes: classes, odors: store.odors)
            }

            if let trainError { Text(trainError).font(.system(size: 13)).foregroundStyle(Theme.ember) }

            Button {
                Task {
                    training = true
                    trainError = await store.trainModel()
                    training = false
                }
            } label: {
                if training { ProgressView().tint(Theme.bg) } else { Text("Entraîner le modèle") }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.mint))
            .disabled(training)
        }
        .glass(padding: 18)
    }
}

/// Matrice de confusion : lignes = odeur réelle, colonnes = odeur prédite.
struct ConfusionMatrixView: View {
    let matrix: [[Int]]
    let classes: [ModelInfo.Meta.Klass]
    let odors: [Odor]

    private func icon(_ k: ModelInfo.Meta.Klass) -> String { odors.first { $0.id == k.odorId }?.icon ?? "?" }

    var body: some View {
        let maxV = Double(matrix.flatMap { $0 }.max() ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("Matrice de confusion").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Ligne = odeur réelle, colonne = odeur prédite").font(.system(size: 11)).foregroundStyle(Theme.muted)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("")
                    ForEach(classes, id: \.odorId) { k in Text(icon(k)).font(.system(size: 13)) }
                }
                ForEach(Array(matrix.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        Text(icon(classes[i])).font(.system(size: 13))
                        ForEach(Array(row.enumerated()), id: \.offset) { j, v in
                            Text("\(v)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(v == 0 ? Theme.muted.opacity(0.5) : Theme.ink)
                                .frame(minWidth: 26, minHeight: 26)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill((i == j ? Theme.mint : Theme.ember).opacity(v == 0 ? 0.04 : 0.15 + 0.6 * Double(v) / maxV)))
                        }
                    }
                }
            }
        }
    }
}
