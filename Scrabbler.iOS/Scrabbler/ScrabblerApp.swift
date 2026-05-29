import SwiftUI
import ScrabblerKit

@main
struct ScrabblerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            switch state.screen {
            case .home:
                HomeView()
            case .boardCorrection:
                BoardCorrectionView()
            case .rackInput:
                RackInputView()
            case .results:
                ResultsView()
            }
        }
        .alert("Scrabbler", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}
