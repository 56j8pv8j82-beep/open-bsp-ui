import SwiftUI

struct CalendarPickerView: View {
    @EnvironmentObject var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var calendars: [GoogleCalendar] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if calendars.isEmpty {
                Text("Nenhum calendário editável encontrado.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(calendars) { cal in
                    Button {
                        preferences.setSelectedCalendar(id: cal.id, summary: cal.summary)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cal.displayName).font(.body)
                                if let tz = cal.timeZone {
                                    Text(tz).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if preferences.selectedCalendarId == cal.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Escolher calendário")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") { dismiss() }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            calendars = try await GoogleCalendarService.shared.listCalendars()
        } catch let err as AppError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
