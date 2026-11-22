import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var server = ""
    @State private var email = "admin@nez.local"
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "nose")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 84)
                            .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text("La bibliothèque des odeurs").font(.title2.bold())
                        Text("Connectez-vous pour voir ce que sent votre maison.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Adresse du serveur", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Serveur")
                } footer: {
                    Text("Sur iPhone, utilisez l'adresse IP de l'ordinateur, par exemple http://192.168.1.50:8000.")
                }

                Section("Compte") {
                    TextField("E-mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { if !password.isEmpty { Task { await submit() } } }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if loading { ProgressView() } else { Text("Se connecter").bold() }
                            Spacer()
                        }
                    }
                    .disabled(loading || password.isEmpty)
                }
            }
            .navigationTitle("Connexion")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { if server.isEmpty { server = store.serverURL } }
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
