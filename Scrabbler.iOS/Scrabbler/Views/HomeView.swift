import PhotosUI
import ScrabblerKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: max(32, geometry.size.height * 0.08))

                    Text("Scrabbler")
                        .font(.largeTitle.bold())

                    VStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text("Load from Gallery")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isBusy || state.isDictionaryLoading)

                        Button {
                            state.loadDictionary()
                        } label: {
                            if state.isDictionaryLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 22)
                            } else {
                                Text(dictionaryButtonTitle)
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 22)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isDictionaryReady || state.isDictionaryCacheAvailable || state.isDictionaryLoading || state.isBusy)
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 20)

                    if showDictionaryStatus {
                        VStack(spacing: 4) {
                            Text(state.dictionaryStatus)
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

                    if state.isBusy {
                        ProgressView(state.status)
                    }

                    Spacer(minLength: 24)

                    VStack(spacing: 3) {
                        Text("Build: \(BuildInfo.buildTimestamp)")
                        Text("Configuration: \(BuildInfo.configuration)")
                        Text("Provisioning expires: \(BuildInfo.provisioningExpiration)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .navigationTitle("Home")
        .onChange(of: selectedPhoto) { newValue in
            Task {
                await state.loadPhoto(newValue)
                selectedPhoto = nil
            }
        }
    }

    private var dictionaryButtonTitle: String {
        StatusTextFormatter.dictionaryButtonTitle(
            isReady: state.isDictionaryReady,
            isCacheAvailable: state.isDictionaryCacheAvailable
        )
    }

    private var showDictionaryStatus: Bool {
        guard !state.dictionaryStatus.isEmpty else { return false }
        if state.dictionaryStatus == "Dictionary cache available", state.lastDictionaryLoadTiming.isEmpty {
            return false
        }
        return true
    }
}
