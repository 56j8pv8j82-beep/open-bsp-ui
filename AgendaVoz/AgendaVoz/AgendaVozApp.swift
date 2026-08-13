import SwiftUI
import GoogleSignIn

@main
struct AgendaVozApp: App {

    @StateObject private var auth = GoogleAuthService.shared
    @StateObject private var preferences = UserPreferences.shared

    init() {
        GoogleAuthService.shared.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(preferences)
                .onOpenURL { url in
                    _ = GoogleAuthService.handle(url: url)
                }
        }
    }
}
