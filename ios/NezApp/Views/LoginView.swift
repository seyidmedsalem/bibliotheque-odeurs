import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var server = ""
    @State private var email = "admin@nez.local"
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            GlowBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Spacer(minLength: 50)
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker("Projet IoT · Nez électronique")
                        Text("La bibliothèque\ndes odeurs").font(.display(46)).foregroundStyle(Theme.ink)
                        Rectangle().fill(Theme.gold).frame(width: 64, height: 1.5)
                        Text("Connectez-vous au serveur pour voir ce que sent votre maison.")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted)
                    }

                    VStack(spacing: 14) {
                        field("Serveur", "http://localhost:8000", text: $server, icon: "server.rack", keyboard: .URL)
                        field("E-mail", "admin@nez.local", text: $email, icon: "envelope", keyboard: .emailAddress)
                        HStack(spacing: 12) {
                            Image(systemName: "lock").foregroundStyle(Theme.gold).frame(width: 20)
                            SecureField("Mot de passe", text: $password)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .onSubmit { if !password.isEmpty { Task { await submit() } } }
                        }
                        .glass(padding: 14)
                    }

                    if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(Theme.ember)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if loading { ProgressView().tint(Theme.bg) } else { Text("Se connecter") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(loading || password.isEmpty)

                    Text("Sur iPhone réel, utilisez l'adresse IP de l'ordinateur qui fait tourner le serveur (ex. http://192.168.1.50:8000).")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)

                    HStack {
                        Spacer()
                        Text("Seyid Cheikh").font(.display(16)).foregroundStyle(Theme.gold.opacity(0.8))
                        Spacer()
                    }
                    .padding(.top, 20)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { if server.isEmpty { server = store.serverURL } }
    }

    private func field(_ label: String, _ placeholder: String, text: Binding<String>, icon: String, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.gold).frame(width: 20)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .glass(padding: 14)
        .accessibilityLabel(label)
    }

    private func submit() async {
        loading = true
        error = nil
        do {
            try await store.login(server: server, email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
