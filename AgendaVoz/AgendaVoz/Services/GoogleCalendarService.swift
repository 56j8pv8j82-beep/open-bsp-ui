import Foundation

/// Cliente enxuto para a Google Calendar API v3 usando `URLSession`.
///
/// Escolha deliberada: chamamos a REST API diretamente em vez do SDK
/// `GoogleAPIClientForREST` — sem dependência adicional, controle total sobre
/// requests, retries e tratamento de erros específicos (401 → refresh).
@MainActor
final class GoogleCalendarService {

    static let shared = GoogleCalendarService(auth: .shared)

    private let auth: GoogleAuthService
    private let session: URLSession
    private let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    init(auth: GoogleAuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - API

    func listCalendars() async throws -> [GoogleCalendar] {
        let url = baseURL.appendingPathComponent("users/me/calendarList")
        let data = try await get(url: url)
        let decoded = try JSONDecoder().decode(GoogleCalendarList.self, from: data)
        return decoded.items.filter { $0.isWritable }
    }

    /// Cria um evento no calendário informado. `timeZone` deve ser um IANA
    /// como "America/Sao_Paulo".
    func createEvent(
        calendarId: String,
        parsed: ParsedEvent,
        timeZone: TimeZone
    ) async throws -> GoogleCalendarEventResponse {
        guard let start = parsed.startDate, let end = parsed.endDate else {
            throw AppError.missingTime
        }
        let iso = Self.rfc3339Formatter
        iso.timeZone = timeZone
        let body = GoogleCalendarEventRequest(
            summary: parsed.title,
            description: parsed.notes,
            location: parsed.location,
            start: .init(dateTime: iso.string(from: start), timeZone: timeZone.identifier),
            end: .init(dateTime: iso.string(from: end), timeZone: timeZone.identifier),
            reminders: {
                if let m = parsed.reminderMinutesBefore {
                    return GoogleCalendarEventRequest.Reminders(
                        useDefault: false,
                        overrides: [.init(method: "popup", minutes: m)]
                    )
                }
                return GoogleCalendarEventRequest.Reminders(useDefault: true, overrides: nil)
            }()
        )
        // Detecta possível duplicata em ±5 minutos com mesmo título.
        if try await hasProbableDuplicate(calendarId: calendarId, title: parsed.title, around: start, timeZone: timeZone) {
            throw AppError.duplicateEvent
        }
        guard let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw AppError.calendarNotFound
        }
        let url = baseURL.appendingPathComponent("calendars/\(encodedId)/events")
        let data = try await post(url: url, body: body)
        return try JSONDecoder().decode(GoogleCalendarEventResponse.self, from: data)
    }

    func deleteEvent(calendarId: String, eventId: String) async throws {
        guard
            let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedEv = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw AppError.calendarNotFound }
        let url = baseURL.appendingPathComponent("calendars/\(encodedCal)/events/\(encodedEv)")
        try await request(method: "DELETE", url: url, body: Optional<Empty>.none, expectData: false)
    }

    func updateEvent(
        calendarId: String,
        eventId: String,
        parsed: ParsedEvent,
        timeZone: TimeZone
    ) async throws -> GoogleCalendarEventResponse {
        guard let start = parsed.startDate, let end = parsed.endDate else {
            throw AppError.missingTime
        }
        let iso = Self.rfc3339Formatter
        iso.timeZone = timeZone
        let body = GoogleCalendarEventRequest(
            summary: parsed.title,
            description: parsed.notes,
            location: parsed.location,
            start: .init(dateTime: iso.string(from: start), timeZone: timeZone.identifier),
            end: .init(dateTime: iso.string(from: end), timeZone: timeZone.identifier),
            reminders: parsed.reminderMinutesBefore.map { m in
                GoogleCalendarEventRequest.Reminders(useDefault: false, overrides: [.init(method: "popup", minutes: m)])
            }
        )
        guard
            let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedEv = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw AppError.calendarNotFound }
        let url = baseURL.appendingPathComponent("calendars/\(encodedCal)/events/\(encodedEv)")
        let data = try await request(method: "PATCH", url: url, body: body, expectData: true)
        return try JSONDecoder().decode(GoogleCalendarEventResponse.self, from: data)
    }

    // MARK: - Anti-duplicação simples

    private struct EventsListResponse: Decodable {
        struct Item: Decodable { let summary: String? }
        let items: [Item]?
    }

    private func hasProbableDuplicate(
        calendarId: String,
        title: String,
        around date: Date,
        timeZone: TimeZone
    ) async throws -> Bool {
        let iso = Self.rfc3339Formatter
        iso.timeZone = timeZone
        let start = date.addingTimeInterval(-5 * 60)
        let end = date.addingTimeInterval(5 * 60)
        guard
            let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            var components = URLComponents(url: baseURL.appendingPathComponent("calendars/\(encodedId)/events"),
                                           resolvingAgainstBaseURL: false)
        else { return false }
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: start)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults", value: "10"),
        ]
        guard let url = components.url else { return false }
        do {
            let data = try await get(url: url)
            let list = try JSONDecoder().decode(EventsListResponse.self, from: data)
            let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return list.items?.contains { ($0.summary?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == normalizedTitle } ?? false
        } catch {
            // Falha na checagem NÃO impede criação — só desativa a proteção.
            return false
        }
    }

    // MARK: - Requests internos

    private struct Empty: Encodable {}

    private func get(url: URL) async throws -> Data {
        try await request(method: "GET", url: url, body: Optional<Empty>.none, expectData: true)
    }

    private func post<T: Encodable>(url: URL, body: T) async throws -> Data {
        try await request(method: "POST", url: url, body: body, expectData: true)
    }

    private func request<T: Encodable>(
        method: String,
        url: URL,
        body: T?,
        expectData: Bool,
        retriedAfterAuth: Bool = false
    ) async throws -> Data {
        let token: String
        do { token = try await auth.freshAccessToken() }
        catch { throw AppError.notConnectedToGoogle }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            req.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain,
               [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut].contains(ns.code) {
                throw AppError.networkUnavailable
            }
            throw AppError.unknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown("Resposta inválida do servidor.")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            if !retriedAfterAuth {
                // Uma tentativa de refresh e retry.
                _ = try? await auth.freshAccessToken()
                return try await request(method: method, url: url, body: body, expectData: expectData, retriedAfterAuth: true)
            }
            throw AppError.tokenExpired
        case 404:
            throw AppError.calendarNotFound
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Erro desconhecido"
            throw AppError.googleAPIFailure(status: http.statusCode, message: msg)
        }
    }

    // MARK: - Formatter

    /// RFC3339 com fração; a Google Calendar API aceita "2026-08-20T13:30:00-03:00".
    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
