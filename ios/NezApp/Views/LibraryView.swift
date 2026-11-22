import SwiftUI

/// Toutes les odeurs que le nez connaît.
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var creating = false
    @State private var search = ""

    private var filtered: [Odor] {
        search.isEmpty ? store.odors : store.odors.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { odor in
                        NavigationLink(value: odor) { OdorRow(odor: odor) }
                    }
                } footer: {
                    Text("\(store.odors.count) odeurs. Touchez une odeur pour voir son empreinte et ses détections.")
                }
            }
            .navigationTitle("Bibliothèque")
            .searchable(text: $search, prompt: "Rechercher une odeur")
            .navigationDestination(for: Odor.self) { OdorDetailView(odorId: $0.id) }
            .toolbar {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nouvelle odeur")
            }
            .refreshable { await store.loadOdors() }
            .sheet(isPresented: $creating) { OdorEditor(odor: nil) }
        }
    }
}

struct OdorRow: View {
    let odor: Odor
    var body: some View {
        HStack(spacing: 12) {
            OdorIcon(icon: odor.icon, color: Color(hex: odor.color), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(odor.name).font(.body.weight(.medium))
                Text("\(odor.samples) échantillons · \(odor.detections) détections")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if odor.alertLevel != "none" {
                Image(systemName: Theme.levelIcon(odor.alertLevel)).foregroundStyle(Theme.level(odor.alertLevel))
            }
        }
        .padding(.vertical, 2)
    }
}

struct OdorDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let odorId: Int
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        if let odor = store.odor(odorId) {
            let color = Color(hex: odor.color)
            List {
                Section {
                    VStack(spacing: 8) {
                        OdorIcon(icon: odor.icon, color: color, size: 72)
                        Text(odor.name).font(.title2.bold())
                        if odor.alertLevel != "none" { LevelBadge(level: odor.alertLevel) }
                        if let d = odor.description, !d.isEmpty {
                            Text(d).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Chiffres") {
                    LabeledContent("Échantillons d'apprentissage", value: "\(odor.samples)")
                    LabeledContent("Détections", value: "\(odor.detections)")
                    if let last = odor.lastDetected { LabeledContent("Dernière détection", value: last.relative) }
                    LabeledContent("Alerte", value: Theme.levelName(odor.alertLevel))
                }
                Section {
                    if odor.fingerprint.isEmpty {
                        Text("Pas encore d'échantillon : enregistrez cette odeur dans l'onglet Apprendre.")
                            .foregroundStyle(.secondary)
                    } else {
                        RadarChart(fingerprint: odor.fingerprint, color: color).frame(height: 240).padding(.vertical, 8)
                        NavigationLink("Valeurs détaillées") {
                            FingerprintView(fingerprint: odor.fingerprint, color: color, title: odor.name)
                        }
                    }
                } header: {
                    Text("Empreinte moyenne")
                } footer: {
                    Text("La « signature » de cette odeur : comment chaque capteur réagit en moyenne.")
                }
                if !odor.isAir {
                    Section {
                        Button("Supprimer cette odeur", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(odor.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Modifier") { editing = true } }
            .sheet(isPresented: $editing) { OdorEditor(odor: odor) }
            .confirmationDialog("Supprimer « \(odor.name) » et ses échantillons ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    Task { await store.deleteOdor(odor.id); dismiss() }
                }
            }
        } else {
            ContentUnavailableView("Odeur introuvable", systemImage: "questionmark")
        }
    }
}

/// Création / modification d'une odeur.
struct OdorEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let odor: Odor?

    @State private var name = ""
    @State private var icon = "👃"
    @State private var color = Color.indigo
    @State private var level = "none"
    @State private var details = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex. Lavande)", text: $name)
                    TextField("Emoji", text: $icon)
                    ColorPicker("Couleur", selection: $color, supportsOpacity: false)
                } header: {
                    Text("Odeur")
                }
                Section {
                    Picker("Niveau", selection: $level) {
                        ForEach(["none", "info", "warning", "danger"], id: \.self) { Text(Theme.levelName($0)).tag($0) }
                    }
                } header: {
                    Text("Alerte")
                } footer: {
                    Text("Quand cette odeur est détectée, une alerte de ce niveau est envoyée.")
                }
                Section("Description") {
                    TextField("Optionnel", text: $details, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(odor == nil ? "Nouvelle odeur" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            saving = true
                            let input = OdorInput(name: name.trimmingCharacters(in: .whitespaces), icon: String(icon.prefix(2)),
                                                  color: color.hexString, alertLevel: level, description: details.isEmpty ? nil : details)
                            if await store.saveOdor(input, id: odor?.id) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                guard let odor else { return }
                name = odor.name; icon = odor.icon; color = Color(hex: odor.color)
                level = odor.alertLevel; details = odor.description ?? ""
            }
        }
    }
}
