import SwiftUI

/// Apprendre une nouvelle odeur et entraîner le modèle.
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
            Form {
                if let session, session.status == "active" {
                    recordingSection(session)
                } else {
                    recordSection
                }
                modelSection
                howSection
            }
            .navigationTitle("Apprendre")
            .toolbar { ToolbarItem(placement: .topBarLeading) { DevicePicker() } }
            .refreshable { await store.loadModel(); await store.loadOdors() }
            .sheet(isPresented: $showEditor) { OdorEditor(odor: nil) }
            .onAppear { if odorId == nil { odorId = store.odors.first?.id } }
        }
    }

    // MARK: - Enregistrer

    private var recordSection: some View {
        Section {
            Picker("Odeur", selection: $odorId) {
                ForEach(store.odors) { o in Text("\(o.icon) \(o.name)").tag(Optional(o.id)) }
            }
            Button { showEditor = true } label: { Label("Nouvelle odeur", systemImage: "plus") }
            Stepper(value: $windows, in: 3...40) {
                LabeledContent("Échantillons", value: "\(windows)")
            }
            if store.selectedDevice?.calibrated == false {
                Label("Le nez se calibre, patientez quelques secondes.", systemImage: "hourglass")
                    .foregroundStyle(.orange)
            }
            Button {
                guard let device = store.selectedDevice, let odorId else { return }
                Task { await store.startTraining(deviceId: device.id, odorId: odorId, windows: windows) }
            } label: {
                Text("Démarrer l'enregistrement").frame(maxWidth: .infinity).bold()
            }
            .disabled(odorId == nil || store.selectedDevice == nil)
            if let session, session.status == "done" {
                Label("\(sessionOdor?.name ?? "Odeur") enregistrée (\(session.collected) échantillons).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Enregistrer une odeur")
        } footer: {
            Text("Durée : environ \(windows * 5 + 20) secondes. Approchez l'odeur à 5 cm du nez quand l'enregistrement démarre.")
        }
    }

    private func recordingSection(_ s: TrainingSession) -> some View {
        Section("Enregistrement en cours") {
            HStack(spacing: 14) {
                OdorIcon(icon: sessionOdor?.icon ?? "👃", color: Color(hex: sessionOdor?.color ?? "#5856D6"), size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionOdor?.name ?? "Odeur").font(.headline)
                    Text(s.collected == 0 ? "Présentez l'odeur maintenant…" : "\(s.collected) sur \(s.targetWindows) échantillons")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: s.progress)
            Button("Annuler l'enregistrement", role: .destructive) { Task { await store.cancelTraining() } }
        }
    }

    // MARK: - Modèle

    private var modelSection: some View {
        let info = store.modelInfo
        return Section {
            HStack {
                Text("État")
                Spacer()
                Group {
                    Image(systemName: info?.trained == true ? "checkmark.seal.fill" : "xmark.seal")
                    Text(info?.trained == true ? "Entraîné" : "Pas encore entraîné")
                }
                .foregroundStyle(info?.trained == true ? Color.green : Color.secondary)
            }
            if let acc = info?.meta.accuracy {
                LabeledContent("Précision", value: acc.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("Échantillons", value: "\(info?.meta.nSamples ?? 0)")
            }
            NavigationLink {
                ModelDetailView()
            } label: {
                Text("Détails par odeur")
            }
            if let trainError {
                Text(trainError).foregroundStyle(.red).font(.footnote)
            }
            Button {
                Task {
                    training = true
                    trainError = await store.trainModel()
                    training = false
                }
            } label: {
                HStack {
                    Text("Entraîner le modèle").bold()
                    Spacer()
                    if training { ProgressView() }
                }
            }
            .disabled(training)
        } header: {
            Text("Modèle de reconnaissance")
        } footer: {
            Text("La précision est mesurée sur des exemples que le modèle n'a jamais vus. Réentraînez après chaque nouvel enregistrement.")
        }
    }

    private var howSection: some View {
        Section("Comment ça marche") {
            Label("Laissez le nez à l'air propre : il se calibre seul.", systemImage: "1.circle")
            Label("Choisissez une odeur et démarrez l'enregistrement.", systemImage: "2.circle")
            Label("Présentez l'odeur près du nez pendant l'enregistrement.", systemImage: "3.circle")
            Label("Entraînez le modèle (au moins 2 odeurs, dont « Air ambiant »).", systemImage: "4.circle")
        }
        .font(.subheadline)
    }
}

/// Échantillons par odeur et matrice de confusion.
struct ModelDetailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let info = store.modelInfo
        List {
            Section {
                ForEach(store.odors) { o in
                    let n = info?.samplesPerOdor[String(o.id)] ?? o.samples
                    LabeledContent("\(o.icon) \(o.name)") {
                        Text("\(n)").monospacedDigit().foregroundStyle(n >= 3 ? .primary : .secondary)
                    }
                }
            } header: {
                Text("Échantillons par odeur")
            } footer: {
                Text("Il faut au moins 3 échantillons par odeur. Avec de vrais capteurs, visez 30 à 50.")
            }
            if let matrix = info?.meta.confusionMatrix, let classes = info?.meta.classes, !classes.isEmpty {
                Section {
                    ConfusionMatrixView(matrix: matrix, classes: classes, odors: store.odors)
                        .padding(.vertical, 8)
                } header: {
                    Text("Matrice de confusion")
                } footer: {
                    Text("Ligne = odeur réelle, colonne = odeur prédite. Les bonnes réponses sont sur la diagonale verte.")
                }
            }
        }
        .navigationTitle("Modèle")
        .navigationBarTitleDisplayMode(.inline)
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
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Text("")
                ForEach(classes, id: \.odorId) { k in Text(icon(k)).font(.caption) }
            }
            ForEach(Array(matrix.enumerated()), id: \.offset) { i, row in
                GridRow {
                    Text(icon(classes[i])).font(.caption)
                    ForEach(Array(row.enumerated()), id: \.offset) { j, v in
                        Text("\(v)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(v == 0 ? .secondary : .primary)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill((i == j ? Color.green : Color.orange).opacity(v == 0 ? 0.05 : 0.15 + 0.5 * Double(v) / maxV)))
                    }
                }
            }
        }
    }
}
