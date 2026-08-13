import Foundation
import SwiftUI

/// Estado da tela principal de gravação.
@MainActor
final class RecordingViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        case interpreting
        case creating
        case success(eventLink: String?)
        case error(AppError)
    }

    @Published var phase: Phase = .idle
    @Published var transcript: String = ""
    @Published var pendingConfirmation: ParsedEvent?
    @Published var isPresentingSettings = false
    @Published var isPresentingSignIn = false
    @Published var isPresentingCalendarPicker = false

    let speech: SpeechRecognitionService
    let auth: GoogleAuthService
    let calendarService: GoogleCalendarService
    let preferences: UserPreferences
    let interpreter: CommandInterpreter

    private var speechTask: Task<Void, Never>?

    init(
        speech: SpeechRecognitionService = SpeechRecognitionService(),
        auth: GoogleAuthService = .shared,
        calendarService: GoogleCalendarService = .shared,
        preferences: UserPreferences = .shared,
        interpreter: CommandInterpreter = LocalCommandInterpreter()
    ) {
        self.speech = speech
        self.auth = auth
        self.calendarService = calendarService
        self.preferences = preferences
        self.interpreter = interpreter
    }

    // MARK: - Controle do fluxo

    func toggleRecording() async {
        switch phase {
        case .recording:
            speech.stop()
        default:
            await startRecording()
        }
    }

    func startRecording() async {
        transcript = ""
        do {
            try await speech.requestPermissions()
        } catch let err as AppError {
            phase = .error(err)
            Haptics.error()
            return
        } catch {
            phase = .error(.unknown(error.localizedDescription))
            Haptics.error()
            return
        }
        do {
            let stream = try speech.startRecording()
            phase = .recording
            Haptics.tap(.medium)
            speechTask?.cancel()
            speechTask = Task { [weak self] in
                guard let self else { return }
                var lastText = ""
                for await event in stream {
                    switch event {
                    case .partial(let text):
                        self.transcript = text
                        lastText = text
                    case .final(let text):
                        self.transcript = text
                        await self.interpretAndConfirm(text: text)
                        return
                    case .error(let err):
                        self.phase = .error(err)
                        Haptics.error()
                        return
                    case .finished:
                        if !lastText.isEmpty {
                            await self.interpretAndConfirm(text: lastText)
                        } else {
                            self.phase = .error(.emptyTranscript)
                            Haptics.warning()
                        }
                        return
                    }
                }
            }
        } catch let err as AppError {
            phase = .error(err)
            Haptics.error()
        } catch {
            phase = .error(.unknown(error.localizedDescription))
            Haptics.error()
        }
    }

    private func interpretAndConfirm(text: String) async {
        phase = .interpreting
        do {
            let parsed = try await interpreter.interpret(
                transcript: text,
                referenceDate: Date(),
                timeZone: .current,
                defaultDurationMinutes: preferences.defaultDurationMinutes,
                defaultReminderMinutes: preferences.defaultReminderMinutes
            )
            pendingConfirmation = parsed
            phase = .idle
            Haptics.tap(.light)
        } catch let err as AppError {
            phase = .error(err)
            Haptics.error()
        } catch {
            phase = .error(.unknown(error.localizedDescription))
            Haptics.error()
        }
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
        phase = .idle
        transcript = ""
    }

    func createEvent(from parsed: ParsedEvent) async {
        guard auth.isSignedIn else {
            isPresentingSignIn = true
            phase = .error(.notConnectedToGoogle)
            return
        }
        guard let calendarId = preferences.selectedCalendarId else {
            isPresentingCalendarPicker = true
            phase = .error(.calendarNotSelected)
            return
        }
        pendingConfirmation = nil
        phase = .creating
        do {
            let response = try await calendarService.createEvent(
                calendarId: calendarId,
                parsed: parsed,
                timeZone: .current
            )
            phase = .success(eventLink: response.htmlLink)
            transcript = ""
            Haptics.success()
        } catch let err as AppError {
            phase = .error(err)
            Haptics.error()
        } catch {
            phase = .error(.unknown(error.localizedDescription))
            Haptics.error()
        }
    }

    func reset() {
        phase = .idle
        transcript = ""
    }
}
