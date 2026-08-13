import Foundation

/// Erros de domínio da aplicação com mensagens localizadas em pt-BR.
enum AppError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognitionUnavailable
    case emptyTranscript
    case missingDate
    case missingTime
    case lowConfidence
    case notConnectedToGoogle
    case tokenExpired
    case networkUnavailable
    case googleAPIFailure(status: Int, message: String)
    case calendarNotSelected
    case calendarNotFound
    case duplicateEvent
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Permita o acesso ao microfone em Ajustes para gravar comandos de voz."
        case .speechRecognitionPermissionDenied:
            return "Permita o reconhecimento de fala em Ajustes para transcrever seus comandos."
        case .speechRecognitionUnavailable:
            return "O reconhecimento de fala está indisponível neste dispositivo no momento."
        case .emptyTranscript:
            return "Não consegui ouvir o que você disse. Tente novamente."
        case .missingDate:
            return "Não consegui identificar a data. Tente incluir, por exemplo, 'amanhã' ou 'quinta-feira'."
        case .missingTime:
            return "Não consegui identificar o horário. Diga, por exemplo, 'às 14 horas'."
        case .lowConfidence:
            return "Não tenho certeza sobre o que você quis dizer. Revise antes de criar."
        case .notConnectedToGoogle:
            return "Conecte sua conta do Google Agenda para criar eventos."
        case .tokenExpired:
            return "Sua sessão do Google expirou. Entre novamente."
        case .networkUnavailable:
            return "Sem conexão com a internet. Verifique sua rede e tente de novo."
        case .googleAPIFailure(let status, let message):
            return "Falha na API do Google (\(status)): \(message)"
        case .calendarNotSelected:
            return "Escolha um calendário do Google nas configurações antes de criar o evento."
        case .calendarNotFound:
            return "O calendário selecionado não existe mais. Escolha outro nas configurações."
        case .duplicateEvent:
            return "Já existe um evento parecido neste horário. Confirme antes de criar novamente."
        case .unknown(let message):
            return "Ocorreu um erro inesperado: \(message)"
        }
    }
}
