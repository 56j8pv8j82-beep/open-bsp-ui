import SwiftUI

struct RecordingView: View {
    @ObservedObject var viewModel: RecordingViewModel
    @EnvironmentObject var auth: GoogleAuthService
    @EnvironmentObject var preferences: UserPreferences

    var body: some View {
        VStack(spacing: 24) {
            headerSection
            Spacer(minLength: 0)
            centerSection
            Spacer(minLength: 0)
            footerSection
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: Binding(
            get: { viewModel.pendingConfirmation != nil },
            set: { newValue in
                if !newValue && viewModel.pendingConfirmation != nil {
                    viewModel.cancelConfirmation()
                }
            }
        )) {
            if let parsed = viewModel.pendingConfirmation {
                NavigationStack {
                    ConfirmationView(
                        initial: parsed,
                        onCancel: { viewModel.cancelConfirmation() },
                        onCreate: { edited in
                            // Limpa antes de dismiss para que o setter do
                            // sheet não interprete como cancelamento.
                            viewModel.pendingConfirmation = nil
                            Task { await viewModel.createEvent(from: edited) }
                        }
                    )
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("O que você precisa lembrar?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            if case .recording = viewModel.phase {
                Text("Ouvindo… fale seu compromisso")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Toque no microfone e fale naturalmente")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 24)
    }

    private var centerSection: some View {
        VStack(spacing: 20) {
            MicrophoneButton(phase: viewModel.phase) {
                Task { await viewModel.toggleRecording() }
            }
            .accessibilityLabel(microphoneAccessibilityLabel)
            .accessibilityAddTraits(.isButton)

            transcriptView
        }
    }

    private var transcriptView: some View {
        Group {
            if !viewModel.transcript.isEmpty {
                Text(viewModel.transcript)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .transition(.opacity)
            } else if case .interpreting = viewModel.phase {
                ProgressView("Interpretando…")
                    .progressViewStyle(.circular)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.transcript)
    }

    private var footerSection: some View {
        VStack(spacing: 12) {
            statusBadge
            errorView
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: auth.isSignedIn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(auth.isSignedIn ? .green : .orange)
            if auth.isSignedIn {
                if let cal = preferences.selectedCalendarSummary {
                    Text("Google Agenda • \(cal)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Escolher calendário") {
                        viewModel.isPresentingCalendarPicker = true
                    }
                    .font(.footnote.weight(.semibold))
                }
            } else {
                Button("Conectar Google Agenda") {
                    viewModel.isPresentingSignIn = true
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Capsule().fill(Color(.tertiarySystemBackground))
        )
    }

    @ViewBuilder
    private var errorView: some View {
        if case .error(let err) = viewModel.phase, let message = err.errorDescription {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .transition(.opacity)
        } else if case .success = viewModel.phase {
            Label("Evento criado com sucesso.", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .transition(.opacity)
        }
    }

    private var microphoneAccessibilityLabel: String {
        switch viewModel.phase {
        case .recording: return "Parar gravação"
        default: return "Iniciar gravação"
        }
    }
}

// MARK: - Botão de microfone

private struct MicrophoneButton: View {
    let phase: RecordingViewModel.Phase
    let action: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 220, height: 220)
                        .scaleEffect(pulse ? 1.15 : 0.95)
                        .opacity(pulse ? 0.0 : 0.5)
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulse
                        )
                }
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 160, height: 160)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: isRecording ? 24 : 12,
                            x: 0, y: isRecording ? 8 : 4)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear { pulse = isRecording }
        .onChange(of: isRecording) { _, newValue in
            pulse = newValue
        }
    }

    private var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }
}
