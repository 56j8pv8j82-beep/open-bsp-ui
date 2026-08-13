import Foundation
import Speech
import AVFoundation

/// Serviço de reconhecimento de fala usando os frameworks nativos do iOS
/// (`Speech` + `AVAudioEngine`). Transmite a transcrição em tempo real via um
/// `AsyncStream`, e faz esforço para manter tudo no dispositivo
/// (`requiresOnDeviceRecognition = true` quando disponível).
@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {

    enum Event {
        case partial(String)
        case final(String)
        case error(AppError)
        case finished
    }

    /// Locale padrão — o app é PT-BR, mas segue a preferência de idioma do
    /// usuário caso o dispositivo tenha outro locale suportado configurado.
    static let defaultLocale = Locale(identifier: "pt-BR")

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<Event>.Continuation?

    @Published private(set) var isRecording: Bool = false

    override init() {
        super.init()
        self.recognizer = SFSpeechRecognizer(locale: Self.defaultLocale)
    }

    // MARK: - Permissões

    func requestPermissions() async throws {
        try await requestMicrophonePermission()
        try await requestSpeechPermission()
    }

    private func requestMicrophonePermission() async throws {
        let status: Bool = await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .granted: cont.resume(returning: true)
                case .denied: cont.resume(returning: false)
                case .undetermined:
                    AVAudioApplication.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                @unknown default: cont.resume(returning: false)
                }
            } else {
                let session = AVAudioSession.sharedInstance()
                switch session.recordPermission {
                case .granted: cont.resume(returning: true)
                case .denied: cont.resume(returning: false)
                case .undetermined:
                    session.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                @unknown default: cont.resume(returning: false)
                }
            }
        }
        if !status { throw AppError.microphonePermissionDenied }
    }

    private func requestSpeechPermission() async throws {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { s in cont.resume(returning: s) }
        }
        switch status {
        case .authorized: return
        case .denied, .restricted: throw AppError.speechRecognitionPermissionDenied
        case .notDetermined: throw AppError.speechRecognitionPermissionDenied
        @unknown default: throw AppError.speechRecognitionPermissionDenied
        }
    }

    // MARK: - Ciclo de gravação

    /// Começa a gravar e devolve um `AsyncStream` de eventos. O chamador deve
    /// consumir o stream até o fim; chamar `stop()` encerra o stream com
    /// `.final(_)` (se houver transcrição) ou `.finished`.
    func startRecording() throws -> AsyncStream<Event> {
        guard let recognizer, recognizer.isAvailable else {
            throw AppError.speechRecognitionUnavailable
        }
        stopInternal()

        // Configura sessão de áudio. `.duckOthers` só é válido com
        // .playAndRecord/.playback/.multiRoute — combiná-lo com .record
        // lança em runtime, então mantemos apenas .record.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Remove qualquer tap anterior antes de instalar um novo.
        inputNode.removeTap(onBus: 0)
        // Captura `request` diretamente — SFSpeechAudioBufferRecognitionRequest.append
        // é seguro para chamadas em thread de áudio, e evitamos tocar self a
        // partir do callback (que roda fora do MainActor).
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        let stream = AsyncStream<Event> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stopInternal() }
            }
        }

        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error = error as NSError? {
                    // Cancelamento manual não é erro visível ao usuário.
                    if error.domain == "kAFAssistantErrorDomain" && error.code == 216 { return }
                    self.continuation?.yield(.error(.unknown(error.localizedDescription)))
                    self.continuation?.finish()
                    return
                }
                guard let result else { return }
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.continuation?.yield(.final(text))
                    self.continuation?.finish()
                } else {
                    self.continuation?.yield(.partial(text))
                }
            }
        }

        isRecording = true
        return stream
    }

    /// Encerra a gravação. O `AsyncStream` fecha em seguida com o último
    /// resultado parcial promovido a final, ou apenas `.finished`.
    func stop() {
        guard isRecording else { return }
        // Sinaliza ao Speech que não haverá mais áudio; o handler do
        // `recognitionTask` devolverá o resultado final.
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }

    private func stopInternal() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
