import SwiftUI

/// Réglages : appareils, serveur, déconnexion.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Appareils") {
                    if store.devices.isEmpty {
                        Text("Aucun appareil pour l'instant.").foregroundStyle(Theme.muted)
                    }
                    ForEach(store.devices) { d in
                        NavigationLink { DeviceEditor(device: d) } label: {
                            HStack(spacing: 12) {
                                GlowDot(color: d.online ? Theme.mint : Theme.muted, size: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundStyle(Theme.ink)
                                    Text([d.room, d.online ? stateName(d.state) : (d.lastSeen.map { "vu \($0.relative)" } ?? "jamais vu")]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
                Section("Serveur") {
                    LabeledContent("Adresse", value: store.serverURL)
                    LabeledContent("Temps réel", value: store.liveConnected ? "connecté" : "déconnecté")
                    LabeledContent("Broker MQTT", value: store.health?.mqttConnected == true ? "connecté" : "non connecté")
                    LabeledContent("Modèle", value: store.health?.modelTrained == true ? "entraîné" : "non entraîné")
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { store.logout(); dismiss() }
                }
                Section {
                    VStack(spacing: 4) {
                        Text("La bibliothèque des odeurs").font(.display(18)).foregroundStyle(Theme.ink)
                        Text("Projet IoT de Seyid Cheikh").font(.system(size: 12)).foregroundStyle(Theme.gold)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlowBackground())
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("OK") { dismiss() } }
            .task { await store.loadHealth(); await store.loadDevices() }
        }
    }

    private func stateName(_ s: String) -> String {
        switch s {
        case "online": return "en ligne"
        case "warming": return "en chauffe"
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
                    Text("Pas encore de position réelle").foregroundStyle(Theme.ember)
                }
                Button { placing = true } label: { Label("Placer sur la carte / par GPS", systemImage: "mappin.and.ellipse") }
                Toggle(isOn: following) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suivre la position de ce téléphone")
                        Text("Pour cartographier un quartier en marchant avec le nez.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
            } header: {
                Text("Position réelle (carte olfactive)")
            }
            Section("Actions") {
                Button("Calibrer à l'air propre") {
                    Task { await store.calibrate(device.id); info = "Calibration demandée : laissez le nez à l'air propre ~10 s." }
                }
                Button("Faire clignoter l'appareil") { Task { await store.identify(device.id) } }
                if let info { Text(info).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlowBackground())
        .navigationTitle(device.name)
        .toolbar {
            Button("Enregistrer") {
                Task {
                    await store.updateDevice(device.id, name: name, room: room, lat: current.lat, lon: current.lon)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $placing) { PlaceDeviceView(device: current) }
        .onAppear {
            name = device.name
            room = device.room ?? ""
        }
    }
}
