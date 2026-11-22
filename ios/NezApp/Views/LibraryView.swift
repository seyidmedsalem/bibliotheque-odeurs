import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Odor?
    @State private var creating = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                GlowBackground(colors: [Theme.gold, Theme.rose, Theme.lilac])
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .bottom) {
                            PageHeader(kicker: "\(store.odors.count) odeurs archivées", title: "Bibliothèque", color: Theme.gold)
                            Button { creating = true } label: {
                                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                                    .background(Circle().fill(Theme.gold.opacity(0.15)))
                                    .overlay(Circle().stroke(Theme.gold.opacity(0.6)))
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.odors) { odor in
                                NavigationLink(value: odor) { OdorCard(odor: odor) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
                .refreshable { await store.loadOdors() }
            }
            .navigationDestination(for: Odor.self) { OdorDetailView(odorId: $0.id) }
            .sheet(isPresented: $creating) { OdorEditor(odor: nil) }
        }
    }
}

struct OdorCard: View {
    let odor: Odor
    var body: some View {
        let color = Color(hex: odor.color)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                OdorIcon(icon: odor.icon, color: color, size: 40)
                Spacer()
                if odor.alertLevel != "none" { LevelBadge(level: odor.alertLevel) }
            }
            Text(odor.name).font(.display(20)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            RadarChart(fingerprint: odor.fingerprint, color: color, showLabels: false).frame(height: 90)
            HStack {
                Label("\(odor.samples)", systemImage: "square.stack.3d.up").font(.system(size: 11))
                Spacer()
                Label("\(odor.detections)", systemImage: "scope").font(.system(size: 11))
            }
            .foregroundStyle(Theme.muted)
        }
        .glass(padding: 14)
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
            ZStack {
                GlowBackground(colors: [color, Theme.lilac, color])
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            OdorIcon(icon: odor.icon, color: color, size: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(odor.name).font(.display(34)).foregroundStyle(Theme.ink)
                                LevelBadge(level: odor.alertLevel)
                            }
                        }
                        if let d = odor.description, !d.isEmpty {
                            Text(d).font(.system(size: 15)).foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 12) {
                            StatTile(value: "\(odor.samples)", label: "échantillons\nd'apprentissage", color: color)
                            StatTile(value: "\(odor.detections)", label: "détections\nau total", color: Theme.gold)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Kicker("Empreinte moyenne", color: color)
                            if odor.fingerprint.isEmpty {
                                Text("Pas encore d'échantillon : enregistrez cette odeur dans l'onglet Apprendre.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            RadarChart(fingerprint: odor.fingerprint, color: color).frame(height: 260)
                            ForEach(Channel.allCases) { ch in
                                if let v = odor.fingerprint[ch.rawValue], abs(v) > 0.0001 {
                                    HStack {
                                        Text(ch.label).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text(String(format: "%+.0f %%", v * 100)).font(.system(size: 13).monospacedDigit())
                                            .foregroundStyle(v >= 0 ? Theme.ember : Theme.sky)
                                    }
                                }
                            }
                        }
                        .glass(padding: 18)
                        if let last = odor.lastDetected {
                            Label("Dernière détection \(last.relative)", systemImage: "clock").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        if !odor.isAir {
                            Button("Supprimer cette odeur", role: .destructive) { confirmDelete = true }
                                .buttonStyle(GhostButtonStyle(color: Theme.ember))
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar { Button("Modifier") { editing = true } }
            .sheet(isPresented: $editing) { OdorEditor(odor: odor) }
            .confirmationDialog("Supprimer « \(odor.name) » et ses échantillons ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    Task { await store.deleteOdor(odor.id); dismiss() }
                }
            }
        } else {
            Text("Odeur introuvable").foregroundStyle(Theme.muted)
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
    @State private var color = Theme.lilac
    @State private var level = "none"
    @State private var details = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Odeur") {
                    TextField("Nom (ex. Lavande)", text: $name)
                    TextField("Emoji", text: $icon)
                    ColorPicker("Couleur", selection: $color, supportsOpacity: false)
                }
                Section("Alerte quand elle est détectée") {
                    Picker("Niveau", selection: $level) {
                        ForEach(["none", "info", "warning", "danger"], id: \.self) { Text(Theme.levelName($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Description") {
                    TextField("Optionnel", text: $details, axis: .vertical).lineLimit(2...5)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlowBackground(colors: [color, Theme.lilac, Theme.gold]))
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
