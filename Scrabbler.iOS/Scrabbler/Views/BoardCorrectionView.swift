import SwiftUI
import ScrabblerKit

struct BoardCorrectionView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var correctionsFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            BoardGridView(board: state.board, onTapCell: { row, column in
                state.appendCorrection(row: row, column: column)
                correctionsFocused = true
            })

            TextField("A1=Ł, H8=?, J10=.", text: $state.correctionsText, axis: .vertical)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($correctionsFocused)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            HStack {
                Button("Apply") {
                    state.applyCorrections()
                }
                .buttonStyle(.bordered)

                Button("Continue") {
                    state.screen = .rackInput
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .navigationTitle("Correct board")
    }
}

struct BoardGridView: View {
    let board: ScrabblerKit.Board
    let onTapCell: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let labelSize: CGFloat = 18
            let boardSize = min(geometry.size.width, geometry.size.height) - labelSize
            let cellSize = boardSize / CGFloat(15)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelSize, height: labelSize)
                    ForEach(0..<15, id: \.self) { column in
                        Text(String(UnicodeScalar(UInt8(ascii: "A") + UInt8(column))))
                            .font(.caption2.bold())
                            .frame(width: cellSize, height: labelSize)
                    }
                }

                ForEach(0..<15, id: \.self) { row in
                    HStack(spacing: 0) {
                        Text("\(row + 1)")
                            .font(.caption2.bold())
                            .frame(width: labelSize, height: cellSize)
                        ForEach(0..<15, id: \.self) { column in
                            Button {
                                onTapCell(row, column)
                            } label: {
                                ZStack {
                                    Rectangle()
                                        .fill(board[row, column].letter == nil ? Color(.secondarySystemBackground) : Color.orange.opacity(0.85))
                                        .border(.white, width: 1)
                                    Text(board[row, column].letter.map(String.init) ?? "")
                                        .font(.system(size: max(10, cellSize * 0.48), weight: .bold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
            .frame(width: boardSize + labelSize, height: boardSize + labelSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 8)
    }
}
