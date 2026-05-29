import SwiftUI
import ScrabblerKit

struct BoardCorrectionView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var correctionsFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            BoardGridView(
                board: state.board,
                highlightedCells: state.autoRepairedCellKeys,
                onTapCell: { row, column in
                    state.appendCorrection(row: row, column: column)
                    correctionsFocused = true
                }
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Detected tiles: \(state.detectedTileCount)")
                    .font(.footnote.weight(.semibold))
                if !state.autoRepairStatus.isEmpty {
                    Text("Auto-corrected: \(state.autoRepairStatus)")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !state.boardValidationStatus.isEmpty {
                    Text(state.boardValidationStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

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
    let highlightedCells: Set<String>
    let onTapCell: (Int, Int) -> Void

    init(
        board: ScrabblerKit.Board,
        highlightedCells: Set<String> = [],
        onTapCell: @escaping (Int, Int) -> Void
    ) {
        self.board = board
        self.highlightedCells = highlightedCells
        self.onTapCell = onTapCell
    }

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
                                let isHighlighted = highlightedCells.contains(Self.key(row: row, column: column))
                                ZStack {
                                    Rectangle()
                                        .fill(fillColor(row: row, column: column, highlighted: isHighlighted))
                                        .border(isHighlighted ? Color.accentColor : Color.white, width: isHighlighted ? 2 : 1)
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

    private func fillColor(row: Int, column: Int, highlighted: Bool) -> Color {
        if highlighted {
            return Color.green.opacity(0.75)
        }
        return board[row, column].letter == nil ? Color(.secondarySystemBackground) : Color.orange.opacity(0.85)
    }

    static func key(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }
}
