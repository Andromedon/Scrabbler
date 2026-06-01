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
                    warningCells: warningCellKeys,
                    onTapCell: { row, column in
                        state.appendCorrection(row: row, column: column)
                        correctionsFocused = true
                    }
                )
                .frame(maxHeight: 520)

                boardStatus
                ocrReview
                autoCorrectionsReview
                invalidWordsReview

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
                if !warningCellKeys.isEmpty {
                    Label("\(warningCellKeys.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }

            if !state.lastBoardReadTiming.isEmpty {
                Text(state.lastBoardReadTiming)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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

    private var autoCorrectionsReview: some View {
        Group {
            if !state.autoRepairItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Auto-corrections", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(state.autoRepairItems) { item in
                            Button {
                                state.appendCorrection(row: item.row, column: item.column)
                                correctionsFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(item.coordinate)
                                            .font(.headline.monospacedDigit())
                                        Spacer(minLength: 4)
                                        Text("\(display(item.originalLetter)) → \(display(item.repairedLetter))")
                                            .font(.headline.weight(.semibold))
                                    }
                                    Text(shortReason(item.reason))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.green.opacity(0.55), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
    }

    private var ocrReview: some View {
        Group {
            if !state.ocrReviewItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("OCR review", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 146), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(state.ocrReviewItems) { item in
                            Button {
                                state.appendCorrection(row: item.row, column: item.column)
                                correctionsFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(item.coordinate)
                                            .font(.headline.monospacedDigit())
                                        Spacer(minLength: 4)
                                        Text(display(item.letter))
                                            .font(.headline.weight(.semibold))
                                    }

                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    HStack(spacing: 6) {
                                        Text("\(Int((item.confidence * 100).rounded()))%")
                                        if let digit = item.detectedScoreDigit {
                                            Text("v\(digit)")
                                        }
                                        if !item.candidates.isEmpty {
                                            Text(item.candidates.map(String.init).joined(separator: "/"))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                        }
                                    }
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
    }

    private var invalidWordsReview: some View {
        Group {
            if !state.invalidBoardWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Words to check", systemImage: "text.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(state.invalidBoardWords) { word in
                            Button {
                                state.appendCorrections(word.coordinates)
                                correctionsFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(word.text)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Text("\(word.coordinate) · \(word.coordinates.count) cells")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
    }

    private var warningCellKeys: Set<String> {
        state.reviewCellKeys.union(state.invalidWordCellKeys)
    }

    private func display(_ letter: Character?) -> String {
        letter.map(String.init) ?? "."
    }

    private func shortReason(_ reason: String) -> String {
        reason.replacingOccurrences(of: "dictionary: ", with: "")
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
                                            weight: board[row, column].letter == nil ? .medium : .bold
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
            return Color.green.opacity(0.18)
        case .tripleLetter:
            return Color.blue.opacity(0.16)
        case .doubleWord:
            return Color.orange.opacity(0.18)
        case .tripleWord:
            return Color.red.opacity(0.18)
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
        board[row, column].letter == nil ? max(6, cellSize * 0.22) : max(11, cellSize * 0.52)
    }

    private func textColor(row: Int, column: Int) -> Color {
        guard board[row, column].letter == nil else {
            return .primary
        }

        switch board[row, column].bonus {
        case .doubleLetter:
            return Color.green.opacity(0.62)
        case .tripleLetter:
            return Color.blue.opacity(0.62)
        case .doubleWord:
            return Color.orange.opacity(0.68)
        case .tripleWord:
            return Color.red.opacity(0.64)
        case .none:
            return .clear
        }
    }

    static func key(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }
}
