import SwiftUI

struct RackInputView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var rackFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Rack letters")
                .font(.title.bold())

            TextField("ABCŁ??", text: $state.rackText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($rackFocused)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .padding(.horizontal)

            Button {
                state.solve()
            } label: {
                if state.isBusy {
                    ProgressView()
                } else {
                    Text("Solve")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.isBusy || (!state.isDictionaryReady && !state.isDictionaryCacheAvailable))
            .padding(.horizontal)

            if !state.isDictionaryReady && !state.isDictionaryCacheAvailable {
                Text("Load the dictionary on Home before solving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if state.isBusy, !state.status.isEmpty {
                Text(state.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("Rack")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    state.screen = .boardCorrection
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .onAppear { rackFocused = true }
    }
}
