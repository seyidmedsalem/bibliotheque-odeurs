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
            .tint(.indigo)
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
                .tabItem { Label("Apprendre", systemImage: "brain") }
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
                Image(systemName: Theme.levelIcon(alert.level))
                    .font(.title3)
                    .foregroundStyle(Theme.level(alert.level))
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(.subheadline.weight(.semibold))
                    Text(alert.message).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { store.banner = nil }
            .task(id: alert.id) {
                try? await Task.sleep(for: .seconds(5))
                withAnimation { store.banner = nil }
            }
        }
    }
}
