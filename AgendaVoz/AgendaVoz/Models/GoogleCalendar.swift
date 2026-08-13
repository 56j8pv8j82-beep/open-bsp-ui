import Foundation

/// Representação mínima de um calendário retornado pela Google Calendar API v3
/// (`GET https://www.googleapis.com/calendar/v3/users/me/calendarList`).
struct GoogleCalendar: Identifiable, Hashable, Codable {
    let id: String
    let summary: String
    let primary: Bool?
    let accessRole: String?
    let backgroundColor: String?
    let timeZone: String?

    var isWritable: Bool {
        guard let accessRole else { return false }
        return accessRole == "owner" || accessRole == "writer"
    }

    var displayName: String {
        primary == true ? "\(summary) (principal)" : summary
    }
}

struct GoogleCalendarList: Codable {
    let items: [GoogleCalendar]
}

/// Corpo de requisição para `POST /calendars/{calendarId}/events`.
struct GoogleCalendarEventRequest: Codable {
    struct EventDateTime: Codable {
        let dateTime: String
        let timeZone: String
    }

    struct Reminders: Codable {
        struct Override: Codable {
            let method: String
            let minutes: Int
        }
        let useDefault: Bool
        let overrides: [Override]?
    }

    let summary: String
    let description: String?
    let location: String?
    let start: EventDateTime
    let end: EventDateTime
    let reminders: Reminders?
}

/// Resposta simplificada de criação de evento.
struct GoogleCalendarEventResponse: Codable {
    let id: String
    let htmlLink: String?
    let status: String?
    let summary: String?
}
