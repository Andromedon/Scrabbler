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

            if state.isBusy {
                ProgressView(state.status)
            }

            Text(state.dictionaryStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .navigationTitle("Home")
        .onChange(of: selectedPhoto) { newValue in
            Task { await state.loadPhoto(newValue) }
        }
    }
}
