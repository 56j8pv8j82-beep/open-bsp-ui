import Foundation

/// Resultado da interpretação de um comando de voz em um evento de calendário.
///
/// O parser preenche este modelo a partir da fala do usuário. Campos podem estar
/// ausentes quando a frase for ambígua — cabe à camada de UI perguntar ao usuário
/// para completar antes de criar o evento no Google Calendar.
struct ParsedEvent: Equatable, Hashable {
    var title: String
    var startDate: Date?
    var endDate: Date?
    var location: String?
    var notes: String?
    var reminderMinutesBefore: Int?
    /// Confiança do parser (0.0 a 1.0). Abaixo de `Self.minimumConfidenceToCreate`
    /// a UI deve pedir confirmação/edição obrigatória antes de criar o evento.
    var confidence: Double
    /// Trecho da fala original preservado para depuração e para permitir editar
    /// manualmente sem perder contexto.
    var originalTranscript: String

    static let minimumConfidenceToCreate: Double = 0.55

    var hasCompleteDateTime: Bool {
        startDate != nil && endDate != nil
    }

    var isValidForCreation: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasCompleteDateTime
            && confidence >= Self.minimumConfidenceToCreate
    }
}
