import Foundation
import GoogleSignIn
import UIKit

/// Autenticação Google via GoogleSignIn-iOS SDK oficial.
///
/// - O SDK gerencia o fluxo OAuth 2.0 completo (ASWebAuthenticationSession),
///   troca de código por token, refresh e armazenamento seguro dos tokens
///   (Keychain interno do próprio GIDSignIn).
/// - Nunca lidamos com senha do usuário.
/// - Solicitamos apenas os escopos mínimos necessários para calendário.
@MainActor
final class GoogleAuthService: ObservableObject {

    static let calendarScope = "https://www.googleapis.com/auth/calendar"

    @Published private(set) var currentUser: GIDGoogleUser?
    @Published private(set) var isSignedIn: Bool = false

    static let shared = GoogleAuthService()

    private init() {
        // Restaura sessão anterior automaticamente na abertura do app.
        Task { await restoreSignInIfAvailable() }
    }

    /// Deve ser chamado no `application(_:didFinishLaunchingWithOptions:)` ou
    /// no equivalente da app SwiftUI para que o SDK use o clientID do Info.plist.
    func configureIfNeeded() {
        // Se GIDClientID está no Info.plist, GIDSignIn já lê automaticamente.
        // Este método existe para futuras configurações programáticas.
    }

    /// Restaura sessão anterior (se houver) sem apresentar UI.
    func restoreSignInIfAvailable() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            self.currentUser = nil
            self.isSignedIn = false
            return
        }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            self.currentUser = user
            self.isSignedIn = hasCalendarScope(user)
        } catch {
            self.currentUser = nil
            self.isSignedIn = false
        }
    }

    /// Apresenta o fluxo de login e pede o escopo de Calendar. Retorna o
    /// usuário autenticado com o escopo já concedido.
    @discardableResult
    func signIn(presenting viewController: UIViewController) async throws -> GIDGoogleUser {
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: [Self.calendarScope]
        )
        var user = result.user
        if !hasCalendarScope(user) {
            let extended = try await user.addScopes([Self.calendarScope], presenting: viewController)
            user = extended.user
        }
        self.currentUser = user
        self.isSignedIn = hasCalendarScope(user)
        return user
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        isSignedIn = false
    }

    /// Revoga o consentimento (desconecta a conta do app no lado do Google).
    func disconnect() async throws {
        try await GIDSignIn.sharedInstance.disconnect()
        currentUser = nil
        isSignedIn = false
    }

    /// Retorna um access token válido, fazendo refresh automático se preciso.
    func freshAccessToken() async throws -> String {
        guard let user = currentUser ?? GIDSignIn.sharedInstance.currentUser else {
            throw AppError.notConnectedToGoogle
        }
        let updated = try await user.refreshTokensIfNeeded()
        self.currentUser = updated
        return updated.accessToken.tokenString
    }

    // MARK: - URL handling (para o AppDelegate/@main)

    @discardableResult
    static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Helpers

    private func hasCalendarScope(_ user: GIDGoogleUser) -> Bool {
        guard let scopes = user.grantedScopes else { return false }
        return scopes.contains(Self.calendarScope)
    }
}
