import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: GoogleAuthService
    @EnvironmentObject var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingSignIn = false
    @State private var isPresentingCalendarPicker = false

    var body: some View {
        Form {
            Section("Conta Google") {
                if let user = auth.currentUser {
                    LabeledContent("Conectado") {
                        Text(user.profile?.email ?? "conta Google")
                            .foregroundStyle(.secondary)
                    }
                    Button("Desconectar conta", role: .destructive) {
                        auth.signOut()
                        preferences.resetCalendarSelection()
                    }
                } else {
                    Button("Conectar ao Google Agenda") {
                        isPresentingSignIn = true
                    }
                }
            }

            Section("Calendário padrão") {
                Button {
                    if auth.isSignedIn {
                        isPresentingCalendarPicker = true
                    } else {
                        isPresentingSignIn = true
                    }
                } label: {
                    HStack {
                        Text("Calendário")
                        Spacer()
                        Text(preferences.selectedCalendarSummary ?? "Escolher")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section("Duração padrão dos eventos") {
                Picker("Duração", selection: Binding(
                    get: { DurationOption(rawValue: preferences.defaultDurationMinutes) ?? .sixty },
                    set: { preferences.setDefaultDuration($0.rawValue) }
                )) {
                    ForEach(DurationOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section("Alerta padrão") {
                Picker("Alerta", selection: Binding(
                    get: {
                        if let m = preferences.defaultReminderMinutes {
                            return ReminderOption(rawValue: m) ?? .tenMinutes
                        }
                        return .none
                    },
                    set: { preferences.setDefaultReminder($0.minutes) }
                )) {
                    ForEach(ReminderOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section("Idioma") {
                Picker("Idioma do reconhecimento", selection: Binding(
                    get: { preferences.preferredLanguage },
                    set: { preferences.setPreferredLanguage($0) }
                )) {
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("English (US)").tag("en-US")
                }
            }

            Section("Sobre") {
                LabeledContent("Versão") {
                    Text(appVersion)
                }
                Link("Política de privacidade", destination: URL(string: "https://example.com/privacy")!)
            }
        }
        .navigationTitle("Configurações")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") { dismiss() }
            }
        }
        .sheet(isPresented: $isPresentingSignIn) {
            NavigationStack {
                GoogleSignInView()
                    .environmentObject(auth)
            }
        }
        .sheet(isPresented: $isPresentingCalendarPicker) {
            NavigationStack {
                CalendarPickerView()
                    .environmentObject(preferences)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
