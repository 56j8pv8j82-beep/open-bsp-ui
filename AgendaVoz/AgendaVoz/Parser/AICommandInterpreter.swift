import Foundation

/// Placeholder para uma futura camada de IA (por exemplo, chamando um backend
/// próprio que traga um LLM). Mantido intencionalmente inerte no MVP para não
/// introduzir dependência de rede nem expor chaves de API.
///
/// Quando quiser habilitar: implemente `interpret` chamando o SEU backend
/// (nunca embuta a chave da API no cliente iOS) e faça `AppDependencies` usar
/// esta implementação em vez de `LocalCommandInterpreter`.
struct AICommandInterpreter: CommandInterpreter {

    /// Endpoint HTTPS do SEU backend seguro. Deixe `nil` para desativar a IA.
    let backendEndpoint: URL?
    /// Fallback quando a IA está indisponível ou desligada.
    let fallback: CommandInterpreter

    init(backendEndpoint: URL? = nil, fallback: CommandInterpreter = LocalCommandInterpreter()) {
        self.backendEndpoint = backendEndpoint
        self.fallback = fallback
    }

    func interpret(
        transcript: String,
        referenceDate: Date,
        timeZone: TimeZone,
        defaultDurationMinutes: Int,
        defaultReminderMinutes: Int?
    ) async throws -> ParsedEvent {
        // Sem endpoint configurado → cai no parser local imediatamente.
        guard backendEndpoint != nil else {
            return try await fallback.interpret(
                transcript: transcript,
                referenceDate: referenceDate,
                timeZone: timeZone,
                defaultDurationMinutes: defaultDurationMinutes,
                defaultReminderMinutes: defaultReminderMinutes
            )
        }

        // TODO: quando o backend estiver pronto, faça o request aqui, usando
        // OAuth/JWT do seu app, JAMAIS uma chave de LLM crua embarcada.
        // Enquanto isso, mantém o comportamento seguro do fallback.
        return try await fallback.interpret(
            transcript: transcript,
            referenceDate: referenceDate,
            timeZone: timeZone,
            defaultDurationMinutes: defaultDurationMinutes,
            defaultReminderMinutes: defaultReminderMinutes
        )
    }
}
