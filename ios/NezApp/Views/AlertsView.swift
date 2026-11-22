import SwiftUI

struct AlertsView: View {
    @Environment(AppStore.self) private var store
    @State private var onlyUnread = false

    private var items: [AlertItem] { onlyUnread ? store.alerts.filter { !$0.acknowledged } : store.alerts }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Afficher", selection: $onlyUnread) {
                        Text("Toutes").tag(false)
                        Text("Non lues").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    ForEach(items) { alert in
                        AlertRow(alert: alert)
                            .swipeActions {
                                if !alert.acknowledged {
                                    Button("Lue") { Task { await store.acknowledge(alert) } }.tint(.indigo)
                                }
                            }
                    }
                } footer: {
                    Text("Glissez une alerte vers la gauche pour la marquer comme lue. Ce système ne remplace pas un détecteur de gaz certifié.")
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Rien à signaler", systemImage: "bell.slash",
                                           description: Text("Les fuites de gaz et les odeurs suspectes apparaîtront ici."))
                }
            }
            .navigationTitle("Alertes")
            .toolbar {
                if store.unreadAlerts > 0 {
                    Button("Tout lire") { Task { await store.acknowledgeAll() } }
                }
            }
            .refreshable { await store.loadAlerts() }
        }
    }
}

struct AlertRow: View {
    let alert: AlertItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Theme.levelIcon(alert.level))
                .font(.title3)
                .foregroundStyle(Theme.level(alert.level))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(alert.title).font(.body.weight(alert.acknowledged ? .regular : .semibold))
                    Spacer()
                    if !alert.acknowledged { Circle().fill(.indigo).frame(width: 8, height: 8) }
                }
                Text(alert.message).font(.subheadline).foregroundStyle(.secondary)
                Text(alert.ts.relative).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
