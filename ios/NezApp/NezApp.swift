import SwiftUI

/// La bibliothèque des odeurs - application iOS du nez électronique.
/// Projet de Seyid Cheikh.
@main
struct NezApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isLoggedIn {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environment(store)
            .preferredColorScheme(.dark)
            .tint(Theme.gold)
            .task { await store.start() }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Direct", systemImage: "waveform.path.ecg") }
            LearnView()
                .tabItem { Label("Apprendre", systemImage: "brain.head.profile") }
            LibraryView()
                .tabItem { Label("Bibliothèque", systemImage: "books.vertical") }
            OdorMapView()
                .tabItem { Label("Carte", systemImage: "map") }
            AlertsView()
                .tabItem { Label("Alertes", systemImage: "bell") }
                .badge(store.unreadAlerts)
        }
        .overlay(alignment: .top) { AlertBanner() }
        .alert("Erreur", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active { Task { await store.refreshAll() } }
        }
    }
}

/// Bandeau qui descend quand une nouvelle alerte arrive.
struct AlertBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let alert = store.banner {
            HStack(alignment: .top, spacing: 12) {
                GlowDot(color: Theme.level(alert.level), size: 12).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(alert.message).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.bg.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.level(alert.level).opacity(0.7)))
            .shadow(color: Theme.level(alert.level).opacity(0.4), radius: 16)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { store.banner = nil }
            .task(id: alert.id) {
                try? await Task.sleep(for: .seconds(5))
                withAnimation { store.banner = nil }
            }
        }
    }
}
