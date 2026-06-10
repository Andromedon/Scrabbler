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

            HStack {
                Button("Clear") {
                    state.rackText = ""
                    rackFocused = true
                }
                .buttonStyle(.bordered)
                .disabled(state.rackText.isEmpty)

                if state.isDictionaryReady {
                    Label("Dictionary ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else if state.isDictionaryCacheAvailable {
                    Label("Dictionary cached", systemImage: "internaldrive.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if !state.dictionaryStatus.isEmpty || !state.lastDictionaryLoadTiming.isEmpty {
                VStack(spacing: 4) {
                    if !state.dictionaryStatus.isEmpty {
                        Text(state.dictionaryStatus)
                    }
                    if !state.lastDictionaryLoadTiming.isEmpty {
                        Text(state.lastDictionaryLoadTiming)
                            .font(.caption.monospacedDigit())
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }

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

            if !state.lastSolveTiming.isEmpty {
                Text(state.lastSolveTiming)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    rackFocused = false
                }
            }
        }
        .onAppear { rackFocused = true }
    }
}
