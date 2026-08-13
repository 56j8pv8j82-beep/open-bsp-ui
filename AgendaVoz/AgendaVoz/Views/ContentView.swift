import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: GoogleAuthService
    @EnvironmentObject var preferences: UserPreferences
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        NavigationStack {
            RecordingView(viewModel: viewModel)
                .navigationTitle("Agenda Voz")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.isPresentingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .accessibilityLabel("Configurações")
                        }
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingSettings) {
                    NavigationStack {
                        SettingsView()
                            .environmentObject(auth)
                            .environmentObject(preferences)
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingSignIn) {
                    NavigationStack {
                        GoogleSignInView()
                            .environmentObject(auth)
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingCalendarPicker) {
                    NavigationStack {
                        CalendarPickerView()
                            .environmentObject(preferences)
                    }
                }
        }
    }
}
