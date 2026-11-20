import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("NEWSFLOW").font(.largeTitle.bold())
                Text("Twój osobisty briefing o AI").foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                TextField("E-mail", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Hasło", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
            }
            .textFieldStyle(.roundedBorder)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button(action: signIn) {
                Group { busy ? AnyView(ProgressView()) : AnyView(Text("Zaloguj się").bold()) }
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || email.isEmpty || password.isEmpty)
            Spacer()
            Text("Konto tworzysz w panelu Supabase (Authentication → Users). Rejestracja w aplikacji jest wyłączona.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func signIn() {
        busy = true
        error = nil
        Task {
            do { try await API.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
            catch { self.error = "Logowanie nieudane: \(error.localizedDescription)" }
            busy = false
        }
    }
}
