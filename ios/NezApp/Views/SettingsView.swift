import SwiftUI

/// Réglages : appareils, serveur, déconnexion.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.devices.isEmpty {
                        Text("Aucun appareil pour l'instant.").foregroundStyle(.secondary)
                    }
                    ForEach(store.devices) { d in
                        NavigationLink { DeviceEditor(device: d) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sensor.fill")
                                    .foregroundStyle(d.online ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name)
                                    Text([d.room, d.online ? stateName(d.state) : (d.lastSeen.map { "vu \($0.relative)" } ?? "jamais vu")]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Appareils")
                } footer: {
                    Text("Touchez un nez pour le renommer, lui donner une pièce, le placer sur la carte ou le calibrer.")
                }
                Section("Serveur") {
                    LabeledContent("Adresse", value: store.serverURL)
                    LabeledContent("Temps réel", value: store.liveConnected ? "Connecté" : "Déconnecté")
                    LabeledContent("Capteurs (MQTT)", value: store.health?.mqttConnected == true ? "Connecté" : "Non connecté")
                    LabeledContent("Modèle", value: store.health?.modelTrained == true ? "Entraîné" : "Non entraîné")
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { store.logout(); dismiss() }
                }
                Section {
                    VStack(spacing: 2) {
                        Text("La bibliothèque des odeurs").font(.footnote.weight(.semibold))
                        Text("Projet IoT de Seyid Cheikh").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("OK") { dismiss() }.bold() }
            .task { await store.loadHealth(); await store.loadDevices() }
        }
    }

    private func stateName(_ s: String) -> String {
        switch s {
        case "online": return "en ligne"
        case "warming": return "préchauffage"
        default: return s
        }
    }
}

struct DeviceEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device

    @State private var name = ""
    @State private var room = ""
    @State private var info: String?
    @State private var placing = false

    private var current: Device { store.devices.first { $0.id == device.id } ?? device }
    private var following: Binding<Bool> {
        Binding(get: { store.followDeviceId == device.id },
                set: { store.followDeviceId = $0 ? device.id : nil })
    }

    var body: some View {
        Form {
            Section("Identité") {
                LabeledContent("Identifiant", value: device.id)
                TextField("Nom", text: $name)
                TextField("Pièce (ex. Cuisine)", text: $room)
            }
            Section {
                if let lat = current.lat, let lon = current.lon {
                    LabeledContent("Position", value: String(format: "%.5f, %.5f", lat, lon))
                } else {
                    Label("Pas encore de position", systemImage: "mappin.slash").foregroundStyle(.orange)
                }
                Button { placing = true } label: { Label("Placer sur la carte", systemImage: "mappin.and.ellipse") }
                Toggle("Suivre ma position", isOn: following)
            } header: {
                Text("Position")
            } footer: {
                Text("« Suivre ma position » met à jour la position du nez pendant que vous marchez avec, pour cartographier un quartier.")
            }
            Section {
                Button {
                    Task { await store.calibrate(device.id); info = "Calibration demandée : laissez le nez à l'air propre environ 10 secondes." }
                } label: { Label("Calibrer à l'air propre", systemImage: "wind") }
                Button { Task { await store.identify(device.id) } } label: { Label("Faire clignoter le nez", systemImage: "lightbulb") }
            } header: {
                Text("Actions")
            } footer: {
                if let info { Text(info) }
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Enregistrer") {
                Task {
                    await store.updateDevice(device.id, name: name, room: room, lat: current.lat, lon: current.lon)
                    dismiss()
                }
            }
            .bold()
        }
        .sheet(isPresented: $placing) { PlaceDeviceView(device: current) }
        .onAppear {
            name = device.name
            room = device.room ?? ""
        }
    }
}
