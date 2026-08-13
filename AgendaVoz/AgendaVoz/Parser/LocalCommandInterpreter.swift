import Foundation

/// Interpretador padrão: roda 100% no dispositivo, sem chamadas de rede,
/// sem coletar dados. Suficiente para a maior parte dos comandos simples do
/// MVP.
struct LocalCommandInterpreter: CommandInterpreter {

    private let dateParser: PortugueseDateParser

    init(dateParser: PortugueseDateParser = PortugueseDateParser()) {
        self.dateParser = dateParser
    }

    func interpret(
        transcript: String,
        referenceDate: Date,
        timeZone: TimeZone,
        defaultDurationMinutes: Int,
        defaultReminderMinutes: Int?
    ) async throws -> ParsedEvent {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.emptyTranscript }

        let dtResult = dateParser.parse(text: trimmed, referenceDate: referenceDate, timeZone: timeZone)

        // Detecta se é lembrete ("me lembra …", "me lembre …", "lembrar de …").
        let isReminder = detectReminderPhrase(in: trimmed) != nil

        // Extrai localização "no/na/em …".
        let (locationRange, location) = extractLocation(from: trimmed)

        // Monta lista final de ranges a remover para derivar o título.
        var rangesToRemove = dtResult.recognizedRanges.map { $0.range }
        if let locationRange { rangesToRemove.append(locationRange) }
        if let reminderRange = detectReminderPhrase(in: trimmed) { rangesToRemove.append(reminderRange) }

        var title = removeRanges(from: trimmed, ranges: rangesToRemove)
        title = cleanTitle(title)

        // Se o título ficou vazio, usa a transcrição inteira como fallback.
        if title.isEmpty { title = trimmed }

        // Determina end date.
        var endDate: Date? = nil
        if let start = dtResult.startDate {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            endDate = cal.date(byAdding: .minute, value: max(5, defaultDurationMinutes), to: start)
        }

        // Ajusta confiança final.
        var confidence = dtResult.confidence
        if title.count < 3 { confidence -= 0.1 }
        if !dtResult.hasExplicitTime { confidence -= 0.15 }
        if !dtResult.hasExplicitDate { confidence -= 0.15 }
        confidence = max(0, min(1, confidence))

        return ParsedEvent(
            title: title,
            startDate: dtResult.startDate,
            endDate: endDate,
            location: location,
            notes: isReminder ? "Lembrete criado por voz." : nil,
            reminderMinutesBefore: defaultReminderMinutes,
            confidence: confidence,
            originalTranscript: trimmed
        )
    }

    // MARK: - Helpers

    private func detectReminderPhrase(in text: String) -> Range<String.Index>? {
        let patterns = [
            #"^\s*me\s+lembr[ea]\s+(?:de\s+)?"#,
            #"^\s*lembrar\s+de\s+"#,
            #"^\s*me\s+avisa(?:r)?\s+(?:de\s+|para\s+)?"#,
        ]
        for pat in patterns {
            if let r = text.range(of: pat, options: [.regularExpression, .caseInsensitive]) {
                return r
            }
        }
        return nil
    }

    private func extractLocation(from text: String) -> (Range<String.Index>?, String?) {
        // Heurística conservadora: "no escritório", "na sala 3", "em casa".
        // Para evitar falsos positivos, só ativa quando aparece perto do fim
        // ou após vírgula/verbo comum.
        let pattern = #"(?:^|\s|,)\s*(no|na|em)\s+([a-zà-ú0-9º][a-zà-ú0-9º\s]{1,40})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return (nil, nil)
        }
        let placeRange = match.range(at: 2)
        let matchedRange = match.range
        guard placeRange.location != NSNotFound,
              let swiftPlaceRange = Range(placeRange, in: text),
              let swiftMatchRange = Range(matchedRange, in: text) else {
            return (nil, nil)
        }
        let placeText = text[swiftPlaceRange].trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignora se for muito curto/comum.
        guard placeText.count >= 3 else { return (nil, nil) }
        return (swiftMatchRange, placeText.capitalizedFirst)
    }

    private func removeRanges(from text: String, ranges: [Range<String.Index>]) -> String {
        // Ordena por lower bound descendente para remover sem invalidar índices.
        let sorted = ranges.sorted { $0.lowerBound > $1.lowerBound }
        var result = text
        for r in sorted {
            // Verifica se ainda é válido (pode ter havido sobreposição).
            if r.lowerBound >= result.startIndex && r.upperBound <= result.endIndex {
                result.replaceSubrange(r, with: " ")
            }
        }
        return result
    }

    private func cleanTitle(_ raw: String) -> String {
        var s = raw
        // Remove partículas que sobrariam após retirar data/hora/local.
        let stopwords = [
            #"\b(de|do|da|dos|das|para|pra|sobre|no|na|em|as|às|a|o)\b\s*$"#,
            #"^\s*\b(de|do|da|dos|das|para|pra|sobre|no|na|em|as|às|a|o)\b\s+"#,
            #",\s*"#,
        ]
        var previous = ""
        while previous != s {
            previous = s
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                 .trimmingCharacters(in: .whitespacesAndNewlines)
            for sw in stopwords {
                s = s.replacingOccurrences(of: sw, with: " ", options: [.regularExpression, .caseInsensitive])
            }
        }
        s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:!?")))
        return s.capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = self.first else { return self }
        return String(first).uppercased() + self.dropFirst()
    }
}
