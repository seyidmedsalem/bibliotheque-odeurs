import SwiftUI

struct AlertsView: View {
    @Environment(AppStore.self) private var store
    @State private var onlyUnread = false

    private var items: [AlertItem] { onlyUnread ? store.alerts.filter { !$0.acknowledged } : store.alerts }

    var body: some View {
        NavigationStack {
            ZStack {
                GlowBackground(colors: [Theme.ember, Theme.rose, Theme.lilac])
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(alignment: .bottom) {
                            PageHeader(kicker: "\(store.unreadAlerts) non lues", title: "Alertes", color: Theme.ember)
                            if store.unreadAlerts > 0 {
                                Button("Tout lire") { Task { await store.acknowledgeAll() } }
                                    .buttonStyle(GhostButtonStyle(color: Theme.gold))
                            }
                        }
                        Picker("Filtre", selection: $onlyUnread) {
                            Text("Toutes").tag(false)
                            Text("Non lues").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if items.isEmpty {
                            EmptyState(icon: "bell.slash", title: "Rien à signaler",
                                       message: "Les fuites de gaz, aliments qui se gâtent et odeurs suspectes apparaîtront ici.")
                        }
                        ForEach(items) { alert in AlertRow(alert: alert) }

                        Text("⚠️ Ce système ne remplace pas un détecteur de gaz ou de CO certifié.")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                    .padding(20)
                }
                .refreshable { await store.loadAlerts() }
            }
        }
    }
}

struct AlertRow: View {
    @Environment(AppStore.self) private var store
    let alert: AlertItem

    var body: some View {
        let color = Theme.level(alert.level)
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).shadow(color: color, radius: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    LevelBadge(level: alert.level)
                    Spacer()
                    Text(alert.ts.relative).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Text(alert.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(alert.message).font(.system(size: 13)).foregroundStyle(Theme.muted)
                if !alert.acknowledged {
                    Button("Marquer comme lue") { Task { await store.acknowledge(alert) } }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold).padding(.top, 2)
                }
            }
        }
        .glass(padding: 14)
        .opacity(alert.acknowledged ? 0.55 : 1)
    }
}
