import Foundation

enum DateFormatting {
    static let ptBR = Locale(identifier: "pt_BR")

    static func prettyDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = ptBR
        f.timeZone = timeZone
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: date).capitalized
    }

    static func prettyDateShort(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = ptBR
        f.timeZone = timeZone
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    static func prettyTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = ptBR
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func prettyDurationMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutos" }
        let hours = minutes / 60
        let rem = minutes % 60
        if rem == 0 { return hours == 1 ? "1 hora" : "\(hours) horas" }
        return "\(hours)h\(String(format: "%02d", rem))"
    }
}
