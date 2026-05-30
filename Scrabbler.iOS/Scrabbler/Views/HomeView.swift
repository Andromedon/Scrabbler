import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Scrabbler")
                .font(.largeTitle.bold())

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Load from Gallery")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Button {
                state.loadDictionary()
            } label: {
                if state.isDictionaryLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    Text(dictionaryButtonTitle)
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .buttonStyle(.bordered)
            .disabled(state.isDictionaryReady || state.isDictionaryCacheAvailable || state.isDictionaryLoading)
            .padding(.horizontal)

            if !state.dictionaryStatus.isEmpty {
                Text(state.dictionaryStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if state.isBusy {
                ProgressView(state.status)
            }

            Spacer()
        }
        .navigationTitle("Home")
        .onChange(of: selectedPhoto) { newValue in
            Task { await state.loadPhoto(newValue) }
        }
    }

    private var dictionaryButtonTitle: String {
        if state.isDictionaryReady {
            "Dictionary Loaded"
        } else if state.isDictionaryCacheAvailable {
            "Dictionary Cached"
        } else {
            "Load Dictionary"
        }
    }
}
