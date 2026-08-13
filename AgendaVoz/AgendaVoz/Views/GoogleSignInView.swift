import SwiftUI
import GoogleSignInSwift

struct GoogleSignInView: View {
    @EnvironmentObject var auth: GoogleAuthService
    @Environment(\.dismiss) private var dismiss

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("Conectar ao Google Agenda")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Vamos precisar de acesso ao seu Google Calendar para criar eventos por voz. Nenhuma senha é armazenada — usamos OAuth 2.0.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            if auth.isSignedIn {
                Label("Google Agenda conectado", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Fechar") { dismiss() }
                    .buttonStyle(.borderedProminent)
            } else {
                GoogleSignInButton {
                    Task { await signIn() }
                }
                .frame(height: 52)
                .padding(.horizontal, 32)
                .accessibilityLabel("Continuar com Google")
                .disabled(isSigningIn)
                if isSigningIn {
                    ProgressView().padding(.top, 8)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Conectar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }
        guard let root = topViewController() else {
            errorMessage = "Não foi possível apresentar o login."
            return
        }
        do {
            _ = try await auth.signIn(presenting: root)
        } catch let err as AppError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        var root = scene?.keyWindow?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root
    }
}
