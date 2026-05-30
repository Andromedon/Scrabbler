import SwiftUI
import ScrabblerKit

struct BoardCorrectionView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var correctionsFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BoardGridView(
                    board: state.board,
                    highlightedCells: state.autoRepairedCellKeys,
                    warningCells: state.reviewCellKeys,
                    onTapCell: { row, column in
                        state.appendCorrection(row: row, column: column)
                        correctionsFocused = true
                    }
                )
                .frame(maxHeight: 520)

                boardStatus

                VStack(spacing: 10) {
                    TextField("A1=Ł, H8=?, J10=.", text: $state.correctionsText, axis: .vertical)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($correctionsFocused)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)

                    HStack {
                        Button("Apply") {
                            state.applyCorrections()
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.correctionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear") {
                            state.correctionsText = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.correctionsText.isEmpty)

                        Button("Continue") {
                            state.screen = .rackInput
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 18)
        }
        .navigationTitle("Correct board")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    state.screen = .home
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    correctionsFocused = false
                }
            }
        }
    }

    private var boardStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Detected tiles: \(state.detectedTileCount)")
                    .font(.footnote.weight(.semibold))
                if !state.autoRepairedCellKeys.isEmpty {
                    Label("\(state.autoRepairedCellKeys.count)", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                if !state.reviewCellKeys.isEmpty {
                    Label("\(state.reviewCellKeys.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if !state.autoRepairStatus.isEmpty {
                Text("Auto-corrected: \(state.autoRepairStatus)")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !state.reviewStatus.isEmpty {
                Text(state.reviewStatus)
                    .font(.footnote)
                    .foregroundStyle(.orange)
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
    }
}

struct BoardGridView: View {
    let board: ScrabblerKit.Board
    let highlightedCells: Set<String>
    let warningCells: Set<String>
    let onTapCell: (Int, Int) -> Void

    init(
        board: ScrabblerKit.Board,
        highlightedCells: Set<String> = [],
        warningCells: Set<String> = [],
        onTapCell: @escaping (Int, Int) -> Void
    ) {
        self.board = board
        self.highlightedCells = highlightedCells
        self.warningCells = warningCells
        self.onTapCell = onTapCell
    }

    var body: some View {
        GeometryReader { geometry in
            let labelSize: CGFloat = min(24, max(18, min(geometry.size.width, geometry.size.height) * 0.045))
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
                                let key = Self.key(row: row, column: column)
                                let isHighlighted = highlightedCells.contains(key)
                                let needsReview = warningCells.contains(key)
                                ZStack {
                                    Rectangle()
                                        .fill(fillColor(row: row, column: column, highlighted: isHighlighted, needsReview: needsReview))
                                        .border(borderColor(highlighted: isHighlighted, needsReview: needsReview), width: isHighlighted || needsReview ? 2 : 1)
                                    Text(cellText(row: row, column: column))
                                        .font(.system(
                                            size: textSize(row: row, column: column, cellSize: cellSize),
                                            weight: board[row, column].letter == nil ? .semibold : .bold
                                        ))
                                        .foregroundStyle(textColor(row: row, column: column))
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
        .padding(.horizontal, 6)
    }

    private func fillColor(row: Int, column: Int, highlighted: Bool, needsReview: Bool) -> Color {
        if highlighted {
            return Color.green.opacity(0.75)
        }
        if needsReview {
            return Color.orange.opacity(board[row, column].letter == nil ? 0.35 : 0.65)
        }
        if board[row, column].letter != nil {
            return Color.orange.opacity(0.85)
        }

        switch board[row, column].bonus {
        case .doubleLetter:
            return Color.green.opacity(0.85)
        case .tripleLetter:
            return Color.blue.opacity(0.75)
        case .doubleWord:
            return Color.orange.opacity(0.85)
        case .tripleWord:
            return Color.red.opacity(0.75)
        case .none:
            return Color(.secondarySystemBackground)
        }
    }

    private func borderColor(highlighted: Bool, needsReview: Bool) -> Color {
        if highlighted {
            return Color.green
        }
        if needsReview {
            return Color.yellow
        }
        return Color.white
    }

    private func cellText(row: Int, column: Int) -> String {
        if let letter = board[row, column].letter {
            return String(letter)
        }

        switch board[row, column].bonus {
        case .doubleLetter:
            return "2L"
        case .tripleLetter:
            return "3L"
        case .doubleWord:
            return "2W"
        case .tripleWord:
            return "3W"
        case .none:
            return ""
        }
    }

    private func textSize(row: Int, column: Int, cellSize: CGFloat) -> CGFloat {
        board[row, column].letter == nil ? max(8, cellSize * 0.30) : max(11, cellSize * 0.52)
    }

    private func textColor(row: Int, column: Int) -> Color {
        guard board[row, column].letter == nil else {
            return .primary
        }

        return board[row, column].bonus == .none ? .clear : .white
    }

    static func key(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }
}
