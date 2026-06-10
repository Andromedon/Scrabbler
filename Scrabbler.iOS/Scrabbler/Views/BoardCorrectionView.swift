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
                    highlightedLegendText: "auto",
                    warningCells: warningCellKeys,
                    selectedCellKey: state.selectedCorrectionCellKey,
                    onTapCell: { row, column in
                        state.appendCorrection(row: row, column: column)
                        correctionsFocused = true
                    }
                )
                .frame(maxHeight: 620)

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

                    quickCorrectionPicker

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

    private var quickCorrectionPicker: some View {
        Group {
            if let target = state.selectedCorrectionTarget {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(target.coordinate, systemImage: "square.grid.3x3.square")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Button(".") {
                            state.setSelectedCorrectionValue(".")
                            correctionsFocused = true
                        }
                        .buttonStyle(.bordered)
                        Button("?") {
                            state.setSelectedCorrectionValue("?")
                            correctionsFocused = true
                        }
                        .buttonStyle(.bordered)
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                        spacing: 6
                    ) {
                        ForEach(PolishAlphabet.letters.map(String.init), id: \.self) { letter in
                            Button(letter) {
                                state.setSelectedCorrectionValue(letter)
                                correctionsFocused = true
                            }
                            .buttonStyle(.bordered)
                            .font(.callout.weight(.semibold))
                            .minimumScaleFactor(0.75)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
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

            highlightLegend

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
            if !state.autoRepairStatus.isEmpty {
                Text("Auto-corrections: \(state.autoRepairStatus)")
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
    }

    private var highlightLegend: some View {
        HStack(spacing: 10) {
            legendItem(color: .green, text: "auto")
            legendItem(color: .orange, text: "check")
            legendItem(color: .accentColor, text: "selected")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Board legend: green auto corrected, orange check, accent selected")
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 8, height: 8)
            Text(text)
        }
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
                            .accessibilityLabel(
                                Text("Auto correction \(item.coordinate), \(display(item.originalLetter)) to \(display(item.repairedLetter))")
                            )
                            .accessibilityHint("Adds this cell to the correction field")
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
                            .accessibilityLabel(
                                Text("OCR review \(item.coordinate), \(display(item.letter)), \(item.reason)")
                            )
                            .accessibilityHint("Adds this cell to the correction field")
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
                            .accessibilityLabel(
                                Text("Word to check \(word.text) at \(word.coordinate)")
                            )
                            .accessibilityHint("Adds all word cells to the correction field")
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
        BoardReviewTextFormatter.displayLetter(letter)
    }

    private func shortReason(_ reason: String) -> String {
        BoardReviewTextFormatter.shortRepairReason(reason)
    }
}

struct BoardGridView: View {
    let board: ScrabblerKit.Board
    let highlightedCells: Set<String>
    let highlightedLegendText: String
    let warningCells: Set<String>
    let selectedCellKey: String?
    let onTapCell: (Int, Int) -> Void

    init(
        board: ScrabblerKit.Board,
        highlightedCells: Set<String> = [],
        highlightedLegendText: String = "highlighted",
        warningCells: Set<String> = [],
        selectedCellKey: String? = nil,
        onTapCell: @escaping (Int, Int) -> Void
    ) {
        self.board = board
        self.highlightedCells = highlightedCells
        self.highlightedLegendText = highlightedLegendText
        self.warningCells = warningCells
        self.selectedCellKey = selectedCellKey
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
                                let isSelected = selectedCellKey == key
                                ZStack {
                                    Rectangle()
                                        .fill(fillColor(row: row, column: column, highlighted: isHighlighted, needsReview: needsReview, selected: isSelected))
                                        .border(borderColor(highlighted: isHighlighted, needsReview: needsReview, selected: isSelected), width: isSelected ? 3 : (isHighlighted || needsReview ? 2 : 1))
                                    cellContent(row: row, column: column, cellSize: cellSize)
                                }
                            }
                            .accessibilityLabel(
                                Text(cellAccessibilityLabel(row: row, column: column))
                            )
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

    @ViewBuilder
    private func cellContent(row: Int, column: Int, cellSize: CGFloat) -> some View {
        if let letter = board[row, column].letter {
            Text(String(letter))
                .font(.system(size: max(11, cellSize * 0.52), weight: .bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
        } else if let bonusText = bonusText(row: row, column: column) {
            VStack {
                HStack {
                    Text(bonusText)
                        .font(.system(size: max(5, cellSize * 0.16), weight: .semibold))
                        .foregroundStyle(bonusTextColor(row: row, column: column))
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(.background.opacity(0.32), in: RoundedRectangle(cornerRadius: 3))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(max(1, cellSize * 0.08))
        }
    }

    private func fillColor(row: Int, column: Int, highlighted: Bool, needsReview: Bool, selected: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(board[row, column].letter == nil ? 0.22 : 0.38)
        }
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

    private func borderColor(highlighted: Bool, needsReview: Bool, selected: Bool) -> Color {
        if selected {
            return Color.accentColor
        }
        if highlighted {
            return Color.green
        }
        if needsReview {
            return Color.yellow
        }
        return Color.white
    }

    private func bonusText(row: Int, column: Int) -> String? {
        BoardReviewTextFormatter.bonusText(board[row, column].bonus)
    }

    private func cellAccessibilityLabel(row: Int, column: Int) -> String {
        let key = Self.key(row: row, column: column)
        var parts = [BoardCoordinateFormatter.coordinate(row: row, column: column)]
        if let letter = board[row, column].letter {
            parts.append("letter \(letter)")
        } else if let bonus = bonusText(row: row, column: column) {
            parts.append("bonus \(bonus)")
        } else {
            parts.append("empty")
        }

        if highlightedCells.contains(key) {
            parts.append(highlightedLegendText)
        }
        if warningCells.contains(key) {
            parts.append("check")
        }
        if selectedCellKey == key {
            parts.append("selected")
        }

        return parts.joined(separator: ", ")
    }

    private func bonusTextColor(row: Int, column: Int) -> Color {
        switch board[row, column].bonus {
        case .doubleLetter:
            return Color.green.opacity(0.76)
        case .tripleLetter:
            return Color.blue.opacity(0.76)
        case .doubleWord:
            return Color.orange.opacity(0.82)
        case .tripleWord:
            return Color.red.opacity(0.78)
        case .none:
            return .clear
        }
    }

    static func key(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }
}
