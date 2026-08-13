import Foundation

/// Um pedaço reconhecido na frase original — usado para (a) construir o Date
/// final e (b) remover as expressões de tempo/data do texto restante para
/// derivar o título do evento.
struct RecognizedRange: Equatable {
    let range: Range<String.Index>
    let kind: Kind
    enum Kind: Equatable {
        case date
        case time
        case relativeDateTime
        case location
        case duration
    }
}

/// Resultado do parsing de datas/horários. `startDate` só é populado quando
/// há informação suficiente.
struct DateTimeParseResult {
    var startDate: Date?
    var endDate: Date?
    var hasExplicitTime: Bool
    var hasExplicitDate: Bool
    var recognizedRanges: [RecognizedRange]
    var confidence: Double
}

/// Parser dedicado a expressões temporais em português brasileiro.
///
/// Não é 100% do domínio de NLP, mas cobre o vocabulário do MVP:
/// hoje/amanhã/depois de amanhã, dias da semana, "semana que vem",
/// "daqui a N horas/minutos", "dia N (de MÊS)", "próximo mês",
/// horários "às HH", "às HHh", "às HHh30", "às 9 da manhã", "meio-dia".
struct PortugueseDateParser {

    // MARK: - Vocabulário

    /// Índices de dia da semana no calendário gregoriano (1=Dom … 7=Sáb).
    static let weekdayMap: [String: Int] = [
        "domingo": 1,
        "segunda": 2, "segunda-feira": 2, "segunda feira": 2,
        "terca": 3, "terça": 3, "terca-feira": 3, "terça-feira": 3, "terca feira": 3, "terça feira": 3,
        "quarta": 4, "quarta-feira": 4, "quarta feira": 4,
        "quinta": 5, "quinta-feira": 5, "quinta feira": 5,
        "sexta": 6, "sexta-feira": 6, "sexta feira": 6,
        "sabado": 7, "sábado": 7,
    ]

    static let monthMap: [String: Int] = [
        "janeiro": 1, "fevereiro": 2, "marco": 3, "março": 3, "abril": 4,
        "maio": 5, "junho": 6, "julho": 7, "agosto": 8, "setembro": 9,
        "outubro": 10, "novembro": 11, "dezembro": 12,
    ]

    static let numberWords: [String: Int] = [
        "zero": 0, "uma": 1, "um": 1, "duas": 2, "dois": 2, "tres": 3, "três": 3,
        "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8, "nove": 9,
        "dez": 10, "onze": 11, "doze": 12, "treze": 13, "quatorze": 14, "catorze": 14,
        "quinze": 15, "dezesseis": 16, "dezessete": 17, "dezoito": 18, "dezenove": 19,
        "vinte": 20, "trinta": 30, "quarenta": 40, "cinquenta": 50,
        "meia": 30, // "seis e meia" => 6:30
    ]

    // MARK: - API pública

    func parse(
        text: String,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> DateTimeParseResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "pt_BR")

        var ranges: [RecognizedRange] = []
        var baseDate: Date? = nil
        var timeComponents: (hour: Int, minute: Int)? = nil
        var hasExplicitDate = false
        var hasExplicitTime = false
        var confidence = 0.5

        let lower = text.lowercased()

        // 1) "daqui a N horas/minutos" — resolve tudo de uma vez.
        if let m = matchRelativeInterval(in: lower, originalText: text, calendar: calendar, from: referenceDate) {
            baseDate = m.date
            ranges.append(RecognizedRange(range: m.range, kind: .relativeDateTime))
            hasExplicitDate = true
            hasExplicitTime = true
            confidence = 0.9
        }

        // 2) Datas absolutas/relativas.
        if baseDate == nil {
            if let m = matchNamedDay(in: lower, originalText: text, calendar: calendar, from: referenceDate) {
                baseDate = m.date
                ranges.append(RecognizedRange(range: m.range, kind: .date))
                hasExplicitDate = true
                confidence = max(confidence, 0.75)
            } else if let m = matchWeekday(in: lower, originalText: text, calendar: calendar, from: referenceDate) {
                baseDate = m.date
                ranges.append(RecognizedRange(range: m.range, kind: .date))
                hasExplicitDate = true
                confidence = max(confidence, 0.75)
            } else if let m = matchDayOfMonth(in: lower, originalText: text, calendar: calendar, from: referenceDate) {
                baseDate = m.date
                ranges.append(RecognizedRange(range: m.range, kind: .date))
                hasExplicitDate = true
                confidence = max(confidence, 0.7)
            } else if let m = matchNextWeek(in: lower, originalText: text, calendar: calendar, from: referenceDate) {
                baseDate = m.date
                ranges.append(RecognizedRange(range: m.range, kind: .date))
                hasExplicitDate = true
                confidence = max(confidence, 0.6)
            } else if let m = matchNextMonth(in: lower, originalText: text, calendar: calendar, from: referenceDate) {
                baseDate = m.date
                ranges.append(RecognizedRange(range: m.range, kind: .date))
                hasExplicitDate = true
                confidence = max(confidence, 0.6)
            }
        }

        // 3) Horário (quando não já veio de "daqui a…").
        if !hasExplicitTime, let m = matchTime(in: lower, originalText: text) {
            timeComponents = (m.hour, m.minute)
            ranges.append(RecognizedRange(range: m.range, kind: .time))
            hasExplicitTime = true
            confidence = max(confidence, 0.75)
        }

        // 4) Combina data + hora.
        var startDate: Date? = nil
        if let base = baseDate {
            if let t = timeComponents {
                startDate = calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: base)
            } else if hasExplicitDate && !hasExplicitTime {
                // Data sem horário — não decide sozinho; a UI perguntará.
                startDate = nil
            } else {
                startDate = base
            }
        } else if let t = timeComponents, !hasExplicitDate {
            // Horário sem data — assume hoje, mas se já passou considera amanhã.
            let today = calendar.startOfDay(for: referenceDate)
            if let candidate = calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: today) {
                if candidate > referenceDate {
                    startDate = candidate
                    hasExplicitDate = true
                    confidence = max(confidence, 0.55)
                } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) {
                    startDate = tomorrow
                    hasExplicitDate = true
                    confidence = max(confidence, 0.55)
                }
            }
        }

        return DateTimeParseResult(
            startDate: startDate,
            endDate: nil,
            hasExplicitTime: hasExplicitTime,
            hasExplicitDate: hasExplicitDate,
            recognizedRanges: ranges,
            confidence: startDate == nil ? min(confidence, 0.4) : confidence
        )
    }

    // MARK: - Matchers

    private func matchRelativeInterval(
        in lower: String,
        originalText: String,
        calendar: Calendar,
        from reference: Date
    ) -> (date: Date, range: Range<String.Index>)? {
        // "daqui a N (horas|minutos|dias)" — N pode ser dígito ou palavra.
        let pattern = #"daqui\s+a\s+(\d+|uma?|duas?|três|tres|quatro|cinco|seis|sete|oito|nove|dez|meia)\s+(hora|horas|minuto|minutos|dia|dias)"#
        guard let (matchRange, groups) = firstRegexMatch(pattern: pattern, in: lower) else { return nil }
        guard groups.count >= 3 else { return nil }
        let quantityStr = groups[1]
        let unit = groups[2]
        guard let quantity = Int(quantityStr) ?? Self.numberWords[quantityStr] else { return nil }
        var component: Calendar.Component
        if unit.hasPrefix("hora") { component = .hour }
        else if unit.hasPrefix("minuto") { component = .minute }
        else { component = .day }
        guard let date = calendar.date(byAdding: component, value: quantity, to: reference) else { return nil }
        guard let originalRange = mapToOriginalRange(nsRange: matchRange, in: originalText, lower: lower) else { return nil }
        return (date, originalRange)
    }

    private func matchNamedDay(
        in lower: String,
        originalText: String,
        calendar: Calendar,
        from reference: Date
    ) -> (date: Date, range: Range<String.Index>)? {
        let today = calendar.startOfDay(for: reference)
        let candidates: [(phrase: String, offset: Int)] = [
            ("depois de amanha", 2), ("depois de amanhã", 2),
            ("amanha", 1), ("amanhã", 1),
            ("hoje", 0),
        ]
        for (phrase, offset) in candidates {
            if let r = lower.range(of: "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b",
                                   options: .regularExpression) {
                guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let orig = mapRange(from: r, in: lower, to: originalText)
                return (date, orig)
            }
        }
        return nil
    }

    private func matchWeekday(
        in lower: String,
        originalText: String,
        calendar: Calendar,
        from reference: Date
    ) -> (date: Date, range: Range<String.Index>)? {
        // Ordena por comprimento decrescente para casar "sexta-feira" antes de "sexta".
        let sortedKeys = Self.weekdayMap.keys.sorted { $0.count > $1.count }
        for key in sortedKeys {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
            guard let r = lower.range(of: pattern, options: .regularExpression) else { continue }
            let target = Self.weekdayMap[key]!
            let today = calendar.startOfDay(for: reference)
            let comps = calendar.dateComponents([.weekday], from: today)
            guard let currentWeekday = comps.weekday else { continue }
            var delta = target - currentWeekday
            if delta <= 0 { delta += 7 } // sempre próxima ocorrência
            // "semana que vem quinta" já é tratado por matchNextWeek; aqui é a próxima.
            guard let date = calendar.date(byAdding: .day, value: delta, to: today) else { continue }
            let orig = mapRange(from: r, in: lower, to: originalText)
            return (date, orig)
        }
        return nil
    }

    private func matchDayOfMonth(
        in lower: String,
        originalText: String,
        calendar: Calendar,
        from reference: Date
    ) -> (date: Date, range: Range<String.Index>)? {
        // "dia 20", "dia 20 de agosto", "20 de agosto"
        let patternWithMonth = #"(?:dia\s+)?(\d{1,2})\s+de\s+([a-zà-ú]+)"#
        if let (matchRange, groups) = firstRegexMatch(pattern: patternWithMonth, in: lower),
           groups.count >= 3,
           let day = Int(groups[1]),
           let month = Self.monthMap[stripAccents(groups[2])] ?? Self.monthMap[groups[2]] {
            let today = calendar.startOfDay(for: reference)
            var comps = calendar.dateComponents([.year, .month, .day], from: today)
            let currentYear = comps.year ?? 0
            comps.day = day
            comps.month = month
            comps.year = currentYear
            if var date = calendar.date(from: comps) {
                if date < today {
                    comps.year = currentYear + 1
                    if let next = calendar.date(from: comps) { date = next }
                }
                guard let orig = mapToOriginalRange(nsRange: matchRange, in: originalText, lower: lower) else { return nil }
                return (date, orig)
            }
        }

        let patternDayOnly = #"\bdia\s+(\d{1,2})\b"#
        if let (matchRange, groups) = firstRegexMatch(pattern: patternDayOnly, in: lower),
           groups.count >= 2, let day = Int(groups[1]) {
            let today = calendar.startOfDay(for: reference)
            var comps = calendar.dateComponents([.year, .month, .day], from: today)
            comps.day = day
            if var date = calendar.date(from: comps) {
                if date < today {
                    if let next = calendar.date(byAdding: .month, value: 1, to: date) {
                        date = next
                    }
                }
                guard let orig = mapToOriginalRange(nsRange: matchRange, in: originalText, lower: lower) else { return nil }
                return (date, orig)
            }
        }

        return nil
    }

    private func matchNextWeek(
        in lower: String,
        originalText: String,
        calendar: Calendar,
        from reference: Date
    ) -> (date: Date, range: Range<String.Index>)? {
        let phrase = "semana que vem"
        guard let r = lower.range(of: "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b",
                                  options: .regularExpression) else { return nil }
        // Aponta para segunda-feira da próxima semana como âncora neutra.
        let today = calendar.startOfDay(for: reference)
        let weekday = calendar.component(.weekday, from: today) // 1=Dom
        let daysUntilNextMonday = ((2 - weekday) + 7) % 7 == 0 ? 7 : ((2 - weekday) + 7) % 7
        let effectiveDays = daysUntilNextMonday == 0 ? 7 : daysUntilNextMonday
        guard let date = calendar.date(byAdding: .day, value: effectiveDays, to: today) else { return nil }
        let orig = mapRange(from: r, in: lower, to: originalText)
        return (date, orig)
    }

    private func matchNextMonth(
        in lower: String,
        originalText: String,
        calendar: Calendar,
        from reference: Date
    ) -> (date: Date, range: Range<String.Index>)? {
        let phrases = ["proximo mes", "próximo mês", "mes que vem", "mês que vem"]
        for phrase in phrases {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
            if let r = lower.range(of: pattern, options: .regularExpression) {
                let today = calendar.startOfDay(for: reference)
                guard let date = calendar.date(byAdding: .month, value: 1, to: today) else { continue }
                let orig = mapRange(from: r, in: lower, to: originalText)
                return (date, orig)
            }
        }
        return nil
    }

    // MARK: - Horário

    private struct TimeMatch { let hour: Int; let minute: Int; let range: Range<String.Index> }

    private func matchTime(in lower: String, originalText: String) -> TimeMatch? {
        // Trata primeiro casos especiais.
        if let r = lower.range(of: "\\bmeio[-\\s]?dia\\b", options: .regularExpression) {
            return TimeMatch(hour: 12, minute: 0, range: mapRange(from: r, in: lower, to: originalText))
        }
        if let r = lower.range(of: "\\bmeia[-\\s]?noite\\b", options: .regularExpression) {
            return TimeMatch(hour: 0, minute: 0, range: mapRange(from: r, in: lower, to: originalText))
        }

        // "às 14h30", "as 14:30", "às 14 horas e 30", "às 14h"
        let numericPatterns = [
            #"(?:à|a)s?\s+(\d{1,2})\s*[h:]\s*(\d{2})"#,
            #"(?:à|a)s?\s+(\d{1,2})\s*horas?\s*(?:e\s*)?(\d{1,2})"#,
            #"(?:à|a)s?\s+(\d{1,2})\s*(?:h|horas?|hrs?)\b"#,
            #"(?:à|a)s?\s+(\d{1,2})\b"#,
        ]
        for (idx, pattern) in numericPatterns.enumerated() {
            if let (matchRange, groups) = firstRegexMatch(pattern: pattern, in: lower) {
                guard let hourVal = Int(groups[1]) else { continue }
                var hour = hourVal
                var minute = 0
                if idx <= 1, groups.count >= 3, let m = Int(groups[2]) { minute = m }
                // Aceita "da tarde" / "da noite" / "da manhã" imediatamente após.
                let ampm = detectAmPm(in: lower, afterNSRange: matchRange)
                if let ampm {
                    if ampm == .pm, hour < 12 { hour += 12 }
                    else if ampm == .am, hour == 12 { hour = 0 }
                }
                // 24h heurística: "às 3" bare (sem "h"/"horas"/AM-PM) → assume PM.
                if idx == 3, ampm == nil, hour < 8 {
                    hour += 12
                }
                guard (0...23).contains(hour), (0...59).contains(minute) else { continue }
                guard let orig = mapToOriginalRange(nsRange: matchRange, in: originalText, lower: lower) else { continue }
                return TimeMatch(hour: hour, minute: minute, range: orig)
            }
        }
        return nil
    }

    private enum AmPm { case am, pm }

    private func detectAmPm(in lower: String, afterNSRange: NSRange) -> AmPm? {
        let end = afterNSRange.location + afterNSRange.length
        guard end < (lower as NSString).length else { return nil }
        let tail = (lower as NSString).substring(from: end)
        let head = tail.prefix(30).lowercased()
        if head.contains("da manha") || head.contains("da manhã") || head.contains("da madrugada") {
            return .am
        }
        if head.contains("da tarde") || head.contains("da noite") {
            return .pm
        }
        return nil
    }

    // MARK: - Regex helpers

    /// Executa NSRegularExpression e devolve o NSRange do match + capturas em String.
    private func firstRegexMatch(pattern: String, in text: String) -> (NSRange, [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            let r = match.range(at: i)
            groups.append(r.location == NSNotFound ? "" : nsText.substring(with: r))
        }
        return (match.range, groups)
    }

    /// Converte `Range<String.Index>` de `lower` para o mesmo intervalo em
    /// `original` — como ambos vêm de `original.lowercased()`, os índices
    /// coincidem em Swift para strings ASCII/latinas quando não há mudança de
    /// comprimento; caímos em fallback caso haja divergência.
    private func mapRange(from range: Range<String.Index>, in lower: String, to original: String) -> Range<String.Index> {
        if lower.count == original.count {
            let start = original.index(original.startIndex,
                                       offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
            let end = original.index(original.startIndex,
                                     offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
            return start..<end
        }
        // Fallback conservador: retorna o range inteiro do original.
        return original.startIndex..<original.endIndex
    }

    private func mapToOriginalRange(nsRange: NSRange, in original: String, lower: String) -> Range<String.Index>? {
        guard let lowerRange = Range(nsRange, in: lower) else { return nil }
        return mapRange(from: lowerRange, in: lower, to: original)
    }

    private func stripAccents(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
    }
}
