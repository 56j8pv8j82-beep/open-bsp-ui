import Foundation
import Combine

/// Preferências do usuário persistidas em `UserDefaults`. Nunca armazena tokens
/// — tokens ficam no `KeychainService`.
@MainActor
final class UserPreferences: ObservableObject {
    private enum Key {
        static let selectedCalendarId = "selectedCalendarId"
        static let selectedCalendarSummary = "selectedCalendarSummary"
        static let defaultDurationMinutes = "defaultDurationMinutes"
        static let defaultReminderMinutes = "defaultReminderMinutes"
        static let preferredLanguage = "preferredLanguage"
    }

    static let shared = UserPreferences()

    private let defaults: UserDefaults

    @Published var selectedCalendarId: String?
    @Published var selectedCalendarSummary: String?
    @Published var defaultDurationMinutes: Int
    @Published var defaultReminderMinutes: Int?
    @Published var preferredLanguage: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedCalendarId = defaults.string(forKey: Key.selectedCalendarId)
        self.selectedCalendarSummary = defaults.string(forKey: Key.selectedCalendarSummary)
        let dur = defaults.integer(forKey: Key.defaultDurationMinutes)
        self.defaultDurationMinutes = dur > 0 ? dur : 60
        if defaults.object(forKey: Key.defaultReminderMinutes) == nil {
            self.defaultReminderMinutes = 10
        } else {
            let raw = defaults.integer(forKey: Key.defaultReminderMinutes)
            self.defaultReminderMinutes = raw >= 0 ? raw : nil
        }
        self.preferredLanguage = defaults.string(forKey: Key.preferredLanguage) ?? "pt-BR"
    }

    func setSelectedCalendar(id: String?, summary: String?) {
        selectedCalendarId = id
        selectedCalendarSummary = summary
        defaults.set(id, forKey: Key.selectedCalendarId)
        defaults.set(summary, forKey: Key.selectedCalendarSummary)
    }

    func setDefaultDuration(_ minutes: Int) {
        let clamped = max(5, min(minutes, 24 * 60))
        defaultDurationMinutes = clamped
        defaults.set(clamped, forKey: Key.defaultDurationMinutes)
    }

    func setDefaultReminder(_ minutes: Int?) {
        defaultReminderMinutes = minutes
        if let minutes {
            defaults.set(minutes, forKey: Key.defaultReminderMinutes)
        } else {
            defaults.set(-1, forKey: Key.defaultReminderMinutes)
        }
    }

    func setPreferredLanguage(_ language: String) {
        preferredLanguage = language
        defaults.set(language, forKey: Key.preferredLanguage)
    }

    func resetCalendarSelection() {
        setSelectedCalendar(id: nil, summary: nil)
    }
}

/// Opções fixas apresentadas na tela de configurações.
enum ReminderOption: Int, CaseIterable, Identifiable {
    case none = -1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case oneDay = 1440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Nenhum"
        case .fiveMinutes: return "5 minutos antes"
        case .tenMinutes: return "10 minutos antes"
        case .fifteenMinutes: return "15 minutos antes"
        case .thirtyMinutes: return "30 minutos antes"
        case .oneHour: return "1 hora antes"
        case .oneDay: return "1 dia antes"
        }
    }

    var minutes: Int? {
        self == .none ? nil : rawValue
    }
}

enum DurationOption: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fifteen: return "15 minutos"
        case .thirty: return "30 minutos"
        case .fortyFive: return "45 minutos"
        case .sixty: return "1 hora"
        case .ninety: return "1 hora e 30 minutos"
        case .oneTwenty: return "2 horas"
        }
    }
}
