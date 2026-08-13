import SwiftUI

struct ConfirmationView: View {
    let initial: ParsedEvent
    let onCancel: () -> Void
    let onCreate: (ParsedEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var event: ParsedEvent
    @State private var editingMode = false

    init(initial: ParsedEvent, onCancel: @escaping () -> Void, onCreate: @escaping (ParsedEvent) -> Void) {
        self.initial = initial
        self.onCancel = onCancel
        self.onCreate = onCreate
        _event = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section("Criar na agenda?") {
                if editingMode {
                    TextField("Título", text: $event.title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                    DatePicker(
                        "Início",
                        selection: Binding(
                            get: { event.startDate ?? Date() },
                            set: { newValue in
                                let duration = event.endDate?.timeIntervalSince(event.startDate ?? newValue) ?? 3600
                                event.startDate = newValue
                                event.endDate = newValue.addingTimeInterval(duration)
                            }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.locale, Locale(identifier: "pt_BR"))
                    DatePicker(
                        "Fim",
                        selection: Binding(
                            get: { event.endDate ?? (event.startDate?.addingTimeInterval(3600) ?? Date().addingTimeInterval(3600)) },
                            set: { event.endDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.locale, Locale(identifier: "pt_BR"))
                    TextField("Local (opcional)", text: Binding(
                        get: { event.location ?? "" },
                        set: { event.location = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Notas (opcional)", text: Binding(
                        get: { event.notes ?? "" },
                        set: { event.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                } else {
                    Text(event.title.isEmpty ? "Sem título" : event.title)
                        .font(.title3.weight(.semibold))
                    if let start = event.startDate {
                        Label(DateFormatting.prettyDate(start), systemImage: "calendar")
                        Label(DateFormatting.prettyTime(start), systemImage: "clock")
                        if let end = event.endDate {
                            let minutes = Int(end.timeIntervalSince(start) / 60)
                            Label("Duração: \(DateFormatting.prettyDurationMinutes(max(1, minutes)))",
                                  systemImage: "hourglass")
                        }
                    } else {
                        Label("Data/hora não identificada — edite antes de criar",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    if let notes = event.notes {
                        Label(notes, systemImage: "note.text")
                    }
                    if event.confidence < ParsedEvent.minimumConfidenceToCreate {
                        Label("Interpretação com baixa confiança — revise antes de criar.",
                              systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button(editingMode ? "Terminar edição" : "Editar") {
                    editingMode.toggle()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Confirmar evento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    onCancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Criar") {
                    onCreate(event)
                    dismiss()
                }
                .disabled(!event.isValidForCreation && !editingMode)
            }
        }
    }
}
