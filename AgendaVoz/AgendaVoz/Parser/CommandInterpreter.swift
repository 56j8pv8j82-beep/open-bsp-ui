import Foundation

/// Interpretador de comandos de voz.
///
/// Implementado inicialmente por `LocalCommandInterpreter` (heurísticas em PT-BR
/// rodando no próprio dispositivo). No futuro, `AICommandInterpreter` poderá
/// delegar frases complexas para um backend seguro.
protocol CommandInterpreter: Sendable {
    func interpret(
        transcript: String,
        referenceDate: Date,
        timeZone: TimeZone,
        defaultDurationMinutes: Int,
        defaultReminderMinutes: Int?
    ) async throws -> ParsedEvent
}
