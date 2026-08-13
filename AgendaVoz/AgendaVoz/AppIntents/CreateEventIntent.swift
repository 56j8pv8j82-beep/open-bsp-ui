import AppIntents
import Foundation

/// App Intent para criar um compromisso a partir de uma frase em português —
/// "Ei Siri, criar compromisso no Agenda Voz reunião com Pedro amanhã às 14 horas".
///
/// Requer iOS 17+. A criação real no Google Calendar depende de o usuário já
/// estar autenticado no app; se não estiver, o Intent falha com uma mensagem
/// pedindo para abrir o app e conectar a conta.
@available(iOS 17.0, *)
struct CreateEventIntent: AppIntent {

    static var title: LocalizedStringResource = "Criar compromisso"
    static var description = IntentDescription("Cria um compromisso no Google Agenda a partir de uma frase.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Frase", requestValueDialog: "O que você quer agendar?")
    var phrase: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let interpreter: CommandInterpreter = LocalCommandInterpreter()
        let prefs = UserPreferences.shared
        let auth = GoogleAuthService.shared
        let service = GoogleCalendarService.shared

        let parsed: ParsedEvent
        do {
            parsed = try await interpreter.interpret(
                transcript: phrase,
                referenceDate: Date(),
                timeZone: .current,
                defaultDurationMinutes: prefs.defaultDurationMinutes,
                defaultReminderMinutes: prefs.defaultReminderMinutes
            )
        } catch {
            return .result(dialog: "Não consegui entender a frase. Abra o Agenda Voz e tente pelo botão de microfone.")
        }
        guard parsed.isValidForCreation else {
            return .result(dialog: "Preciso de data e horário claros. Abra o Agenda Voz para completar.")
        }
        guard auth.isSignedIn else {
            return .result(dialog: "Você precisa conectar sua conta do Google no Agenda Voz primeiro.")
        }
        guard let calendarId = prefs.selectedCalendarId else {
            return .result(dialog: "Escolha um calendário nas configurações do Agenda Voz.")
        }
        do {
            _ = try await service.createEvent(calendarId: calendarId, parsed: parsed, timeZone: .current)
            let start = parsed.startDate!
            let when = "\(DateFormatting.prettyDateShort(start)) às \(DateFormatting.prettyTime(start))"
            return .result(dialog: "Pronto. Criei \"\(parsed.title)\" em \(when).")
        } catch let err as AppError {
            let msg = err.errorDescription ?? "Falha ao criar o evento."
            return .result(dialog: "\(msg)")
        } catch {
            return .result(dialog: "Falha ao criar o evento: \(error.localizedDescription)")
        }
    }
}

@available(iOS 17.0, *)
struct AgendaVozShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateEventIntent(),
            phrases: [
                "Criar compromisso no \(.applicationName)",
                "Agendar no \(.applicationName)",
                "Novo evento no \(.applicationName)",
            ],
            shortTitle: "Criar compromisso",
            systemImageName: "calendar.badge.plus"
        )
    }
}
