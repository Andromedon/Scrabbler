import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct LetterCandidate: Equatable, Sendable {
    public let letter: Character
    public let distance: Double
    public let matchedScoreDigit: Int?

    public init(letter: Character, distance: Double, matchedScoreDigit: Int? = nil) {
        self.letter = PolishAlphabet.normalizeLetter(letter)
        self.distance = distance
        self.matchedScoreDigit = matchedScoreDigit
    }
}

public struct CellRead: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let letter: Character?
    public let isBlank: Bool
    public let confidence: Double
    public let candidates: [LetterCandidate]
    public let detectedScoreDigit: Int?

    public init(
        row: Int,
        column: Int,
        letter: Character?,
        isBlank: Bool = false,
        confidence: Double = 0,
        candidates: [LetterCandidate] = [],
        detectedScoreDigit: Int? = nil
    ) {
        self.row = row
        self.column = column
        self.letter = letter.map(PolishAlphabet.normalizeLetter)
        self.isBlank = isBlank
        self.confidence = confidence
        self.candidates = candidates
        self.detectedScoreDigit = detectedScoreDigit
    }
}

public struct BoardReadResult: Equatable, Sendable {
    public let board: Board
    public let cells: [CellRead]
    public let appliedRepairs: [BoardRepair]

    public init(board: Board, cells: [CellRead] = [], appliedRepairs: [BoardRepair] = []) {
        self.board = board
        self.cells = cells
        self.appliedRepairs = appliedRepairs
    }
}

public struct BoardRepair: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let originalLetter: Character?
    public let repairedLetter: Character?
    public let reason: String
}

public protocol BoardImageReading: Sendable {
    func readBoard(from imageURL: URL, bonuses: [[BonusType]]) async throws -> BoardReadResult
}

public enum BoardImageReaderError: LocalizedError {
    case imageCouldNotBeLoaded
    case textRecognitionFailed

    public var errorDescription: String? {
        switch self {
        case .imageCouldNotBeLoaded:
            "Could not load the selected board image."
        case .textRecognitionFailed:
            "Could not recognize any board letters in the selected image."
        }
    }
}

public struct NativeBoardImageReader: BoardImageReading {
    private static let defaultGlyphRecognizer = try? TileGlyphRecognizer(letterValues: BundledDataLoader.loadLetterValues())

    public init() {}

    public func readBoard(from imageURL: URL, bonuses: [[BonusType]]) async throws -> BoardReadResult {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BoardImageReaderError.imageCouldNotBeLoaded
        }

        let observations = try recognizeText(in: imageURL)
        let mapper = BoardImageMapper(width: image.width, height: image.height)
        let sampler = BoardColorSampler(image: image, mapper: mapper)
        let glyphRecognizer = Self.defaultGlyphRecognizer

        var readsByCell: [String: CellRead] = [:]
        for observation in observations {
            guard let recognized = observation.topCandidates(1).first else { continue }
            let text = recognized.string
            if isBonusLabel(text) { continue }

            for range in text.characterRanges {
                let characterText = String(text[range])
                guard characterText.count == 1,
                      let letter = characterText.first,
                      PolishAlphabet.isPolishLetter(letter),
                      let box = try? recognized.boundingBox(for: range),
                      let coordinate = mapper.coordinate(for: box.boundingBox),
                      sampler.cellLooksOccupied(row: coordinate.row, column: coordinate.column) else {
                    continue
                }

                let normalized = PolishAlphabet.normalizeLetter(letter)
                let confidence = Double(recognized.confidence)
                let key = "\(coordinate.row):\(coordinate.column)"
                let candidate = CellRead(
                    row: coordinate.row,
                    column: coordinate.column,
                    letter: normalized,
                    confidence: confidence,
                    candidates: [LetterCandidate(letter: normalized, distance: 1 - confidence)]
                )

                if let existing = readsByCell[key] {
                    if candidate.confidence > existing.confidence {
                        readsByCell[key] = candidate
                    }
                } else {
                    readsByCell[key] = candidate
                }
            }
        }

        for row in 0..<Board.size {
            for column in 0..<Board.size {
                let key = "\(row):\(column)"
                guard sampler.cellLooksOccupied(row: row, column: column) else {
                    continue
                }

                let glyphRead = glyphRecognizer?.recognize(row: row, column: column, mapper: mapper, sampler: sampler)
                if let existing = readsByCell[key] {
                    readsByCell[key] = merge(existing: existing, glyph: glyphRead)
                } else {
                    readsByCell[key] = glyphRead ?? CellRead(
                        row: row,
                        column: column,
                        letter: nil,
                        confidence: 0
                    )
                }
            }
        }

        var board = Board(bonuses: bonuses)
        let cells = readsByCell.values.sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            return $0.column < $1.column
        }

        for cell in cells {
            if let letter = cell.letter {
                board = board.setCell(row: cell.row, column: cell.column, letter: letter, isBlank: cell.isBlank)
            }
        }

        guard !cells.isEmpty else {
            throw BoardImageReaderError.textRecognitionFailed
        }

        return BoardReadResult(board: board, cells: cells)
    }

    private func merge(existing: CellRead, glyph: CellRead?) -> CellRead {
        guard let glyph else { return existing }

        let selectedLetter: Character?
        let selectedConfidence: Double
        if glyph.letter != nil && (existing.letter == nil || glyph.confidence > existing.confidence + 0.15) {
            selectedLetter = glyph.letter
            selectedConfidence = glyph.confidence
        } else {
            selectedLetter = existing.letter
            selectedConfidence = existing.confidence
        }

        return CellRead(
            row: existing.row,
            column: existing.column,
            letter: selectedLetter,
            isBlank: existing.isBlank,
            confidence: selectedConfidence,
            candidates: mergeCandidates(existing.candidates, glyph.candidates),
            detectedScoreDigit: glyph.detectedScoreDigit ?? existing.detectedScoreDigit
        )
    }

    private func mergeCandidates(_ first: [LetterCandidate], _ second: [LetterCandidate]) -> [LetterCandidate] {
        var byLetter: [Character: LetterCandidate] = [:]
        for candidate in first + second {
            if let existing = byLetter[candidate.letter], existing.distance <= candidate.distance {
                continue
            }
            byLetter[candidate.letter] = candidate
        }

        return byLetter.values.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return String($0.letter) < String($1.letter)
        }
    }

    private func recognizeText(in imageURL: URL) throws -> [VNRecognizedTextObservation] {
        let accurateRequest = makeTextRequest(recognitionLevel: .accurate)
        let fastRequest = makeTextRequest(recognitionLevel: .fast)
        let handler = VNImageRequestHandler(url: imageURL)
        try handler.perform([accurateRequest, fastRequest])
        return (accurateRequest.results ?? []) + (fastRequest.results ?? [])
    }

    private func makeTextRequest(recognitionLevel: VNRequestTextRecognitionLevel) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["pl-PL", "en-US"]
        request.customWords = PolishAlphabet.letters.map(String.init)
        request.minimumTextHeight = 0.005
        return request
    }

    private func isBonusLabel(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.count <= 3 && normalized.contains(where: \.isNumber) {
            return true
        }
        return ["DL", "TL", "DW"].contains(normalized)
    }
}

public struct DictionaryBoardRepairer: Sendable {
    private let dictionary: WordDictionary
    private let letterValues: [Character: Int]

    public init(dictionary: WordDictionary, letterValues: [Character: Int] = [:]) {
        self.dictionary = dictionary
        self.letterValues = letterValues
    }

    public func invalidWords(on board: Board) -> [BoardWord] {
        BoardWordExtractor.extractWords(from: board).filter { !dictionary.contains($0.text) }
    }

    public func repair(_ result: BoardReadResult) -> BoardReadResult {
        var board = result.board
        var repairs: [BoardRepair] = []
        let cellsByKey = Dictionary(uniqueKeysWithValues: result.cells.map { (Self.key(row: $0.row, column: $0.column), $0) })

        for _ in 0..<32 {
            let invalidWords = invalidWords(on: board)
            guard let candidate = bestRepair(on: board, invalidWords: invalidWords, cellsByKey: cellsByKey) else {
                break
            }

            if candidate.repairs.allSatisfy({ board[$0.row, $0.column].letter == $0.repairedLetter }) {
                break
            }

            board = candidate.board
            repairs.append(contentsOf: candidate.repairs)
        }

        guard !repairs.isEmpty else { return result }

        let repairedByKey = Dictionary(uniqueKeysWithValues: repairs.map { (Self.key(row: $0.row, column: $0.column), $0) })
        let updatedCells = result.cells.map { cell in
            guard let repair = repairedByKey[Self.key(row: cell.row, column: cell.column)] else {
                return cell
            }

            return CellRead(
                row: cell.row,
                column: cell.column,
                letter: repair.repairedLetter,
                isBlank: cell.isBlank,
                confidence: max(cell.confidence, 0.70),
                candidates: cell.candidates,
                detectedScoreDigit: cell.detectedScoreDigit
            )
        }

        return BoardReadResult(board: board, cells: updatedCells, appliedRepairs: result.appliedRepairs + repairs)
    }

    private func bestRepair(on board: Board, invalidWords: [BoardWord], cellsByKey: [String: CellRead]) -> RepairCandidate? {
        let rawCandidates = (invalidWords
            .flatMap { repairCandidates(for: $0, on: board, cellsByKey: cellsByKey) }
            + gapRepairCandidates(on: board, cellsByKey: cellsByKey))
            .filter { candidate in
                candidate.repairs.flatMap { affectedWords(on: candidate.board, row: $0.row, column: $0.column) }
                    .allSatisfy { dictionary.contains($0.text) }
            }

        var deduplicated: [String: RepairCandidate] = [:]
        for candidate in rawCandidates {
            let key = candidate.repairs
                .map { "\($0.row):\($0.column):\($0.originalLetter.map(String.init) ?? "."):\($0.repairedLetter.map(String.init) ?? ".")" }
                .sorted()
                .joined(separator: "|")
            if let existing = deduplicated[key] {
                if candidate.invalidWordReduction > existing.invalidWordReduction ||
                    candidate.invalidWordReduction == existing.invalidWordReduction && candidate.score > existing.score {
                    deduplicated[key] = candidate
                }
            } else {
                deduplicated[key] = candidate
            }
        }

        let candidates = Array(deduplicated.values)
            .sorted { lhs, rhs in
                if lhs.invalidWordReduction != rhs.invalidWordReduction {
                    return lhs.invalidWordReduction > rhs.invalidWordReduction
                }
                return lhs.score > rhs.score
            }

        guard let best = candidates.first, best.invalidWordReduction > 0 else { return nil }
        if candidates.count > 1,
           candidates[0].invalidWordReduction == candidates[1].invalidWordReduction,
           abs(candidates[0].score - candidates[1].score) < 0.001 {
            return nil
        }

        return best
    }

    private func gapRepairCandidates(on board: Board, cellsByKey: [String: CellRead]) -> [RepairCandidate] {
        var candidates: [RepairCandidate] = []
        for row in 0..<Board.size {
            for column in 0..<Board.size {
                guard board[row, column].letter == nil,
                      let cell = cellsByKey[Self.key(row: row, column: column)],
                      cell.letter == nil else {
                    continue
                }

                if let horizontal = gapRepairCandidate(
                    on: board,
                    row: row,
                    column: column,
                    direction: .horizontal,
                    cellsByKey: cellsByKey
                ) {
                    candidates.append(horizontal)
                }

                if let vertical = gapRepairCandidate(
                    on: board,
                    row: row,
                    column: column,
                    direction: .vertical,
                    cellsByKey: cellsByKey
                ) {
                    candidates.append(vertical)
                }
            }
        }
        return candidates
    }

    private func gapRepairCandidate(
        on board: Board,
        row: Int,
        column: Int,
        direction: Direction,
        cellsByKey: [String: CellRead]
    ) -> RepairCandidate? {
        let before = direction == .horizontal ? (row, column - 1) : (row - 1, column)
        let after = direction == .horizontal ? (row, column + 1) : (row + 1, column)
        guard isOccupied(board, row: before.0, column: before.1),
              isOccupied(board, row: after.0, column: after.1) else {
            return nil
        }

        var startRow = row
        var startColumn = column
        while true {
            let previous = direction == .horizontal ? (startRow, startColumn - 1) : (startRow - 1, startColumn)
            guard isOccupied(board, row: previous.0, column: previous.1) else { break }
            startRow = previous.0
            startColumn = previous.1
        }

        var cells: [(row: Int, column: Int, letter: Character?)] = []
        var currentRow = startRow
        var currentColumn = startColumn
        var emptyCount = 0
        while Board.isInside(row: currentRow, column: currentColumn) {
            let letter = currentRow == row && currentColumn == column
                ? nil
                : board[currentRow, currentColumn].letter
            if letter == nil && (currentRow != row || currentColumn != column) {
                break
            }
            if letter == nil {
                emptyCount += 1
            }
            cells.append((currentRow, currentColumn, letter))

            if direction == .horizontal {
                currentColumn += 1
            } else {
                currentRow += 1
            }
            if emptyCount > 1 {
                break
            }
        }

        guard emptyCount == 1,
              cells.count > 2 else {
            return nil
        }

        let beforeInvalid = invalidWords(on: board).count
        let matches = gapCellVariants(cells, cellsByKey: cellsByKey)
            .flatMap { variant -> [RepairCandidate] in
                guard let words = dictionary.wordsByLength[variant.cells.count] else { return [] }
                return words.compactMap { word in
                    buildGapCandidate(
                        on: board,
                        cells: variant.cells,
                        droppedEdgeCell: variant.droppedEdgeCell,
                        word: word,
                        gapRow: row,
                        gapColumn: column,
                        cellsByKey: cellsByKey,
                        beforeInvalid: beforeInvalid
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.invalidWordReduction != rhs.invalidWordReduction {
                    return lhs.invalidWordReduction > rhs.invalidWordReduction
                }
                return lhs.score > rhs.score
            }

        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private func gapCellVariants(
        _ cells: [(row: Int, column: Int, letter: Character?)],
        cellsByKey: [String: CellRead]
    ) -> [(cells: [(row: Int, column: Int, letter: Character?)], droppedEdgeCell: (row: Int, column: Int, letter: Character?)?)] {
        var variants: [(cells: [(row: Int, column: Int, letter: Character?)], droppedEdgeCell: (row: Int, column: Int, letter: Character?)?)] = [
            (cells, nil)
        ]

        if let first = cells.first,
           canDropEdgeCell(first, cellsByKey: cellsByKey),
           cells.dropFirst().count > 2 {
            variants.append((Array(cells.dropFirst()), first))
        }

        if let last = cells.last,
           canDropEdgeCell(last, cellsByKey: cellsByKey),
           cells.dropLast().count > 2 {
            variants.append((Array(cells.dropLast()), last))
        }

        return variants
    }

    private func canDropEdgeCell(
        _ cell: (row: Int, column: Int, letter: Character?),
        cellsByKey: [String: CellRead]
    ) -> Bool {
        guard let letter = cell.letter,
              let read = cellsByKey[Self.key(row: cell.row, column: cell.column)],
              read.letter == letter else {
            return false
        }

        return read.confidence < 0.72
    }

    private func buildGapCandidate(
        on board: Board,
        cells: [(row: Int, column: Int, letter: Character?)],
        droppedEdgeCell: (row: Int, column: Int, letter: Character?)?,
        word: String,
        gapRow: Int,
        gapColumn: Int,
        cellsByKey: [String: CellRead],
        beforeInvalid: Int
    ) -> RepairCandidate? {
        let expectedLetters = Array(word)
        guard expectedLetters.count == cells.count else { return nil }

        var repairedBoard = board
        var repairs: [BoardRepair] = []
        var score = Double(word.count)

        if let droppedEdgeCell,
           let droppedLetter = droppedEdgeCell.letter {
            repairedBoard = repairedBoard.setCell(row: droppedEdgeCell.row, column: droppedEdgeCell.column, letter: nil)
            repairs.append(BoardRepair(
                row: droppedEdgeCell.row,
                column: droppedEdgeCell.column,
                originalLetter: droppedLetter,
                repairedLetter: nil,
                reason: "dictionary: edge false positive"
            ))
            score += 0.45
        }

        for index in expectedLetters.indices {
            let cell = cells[index]
            let expected = expectedLetters[index]
            if cell.row == gapRow && cell.column == gapColumn {
                repairedBoard = repairedBoard.setCell(row: cell.row, column: cell.column, letter: expected)
                repairs.append(BoardRepair(
                    row: cell.row,
                    column: cell.column,
                    originalLetter: nil,
                    repairedLetter: expected,
                    reason: "dictionary: \(word)"
                ))
                score += 0.75
                continue
            }

            if cell.letter == expected {
                continue
            }

            guard let current = cell.letter,
                  let read = cellsByKey[Self.key(row: cell.row, column: cell.column)],
                  canSubstituteGapNeighbor(read, current: current, expected: expected, score: &score) else {
                return nil
            }

            repairedBoard = repairedBoard.setCell(row: cell.row, column: cell.column, letter: expected)
            repairs.append(BoardRepair(
                row: cell.row,
                column: cell.column,
                originalLetter: current,
                repairedLetter: expected,
                reason: "dictionary: \(word)"
            ))
        }

        guard !repairs.isEmpty,
              repairs.filter({ $0.originalLetter != nil }).count <= 1 else {
            return nil
        }

        let affected = repairs.flatMap { affectedWords(on: repairedBoard, row: $0.row, column: $0.column) }
        guard !affected.isEmpty, affected.allSatisfy({ dictionary.contains($0.text) }) else {
            return nil
        }

        let afterInvalid = invalidWords(on: repairedBoard).count
        return RepairCandidate(
            board: repairedBoard,
            repairs: repairs,
            invalidWordReduction: max(1, beforeInvalid - afterInvalid),
            score: score
        )
    }

    private func canSubstituteGapNeighbor(
        _ cell: CellRead,
        current: Character,
        expected: Character,
        score: inout Double
    ) -> Bool {
        guard cell.confidence < 0.82,
              replacementLetters(for: cell, current: current).contains(expected) else {
            return false
        }

        score += scoreReplacement(cell: cell, replacement: expected)
        return true
    }

    private func repairCandidates(for word: BoardWord, on board: Board, cellsByKey: [String: CellRead]) -> [RepairCandidate] {
        guard !dictionary.contains(word.text) else { return [] }

        var candidates: [RepairCandidate] = []
        let letters = Array(word.text)
        for index in letters.indices {
            let coordinate = word.coordinates[index]
            guard let cell = cellsByKey[Self.key(row: coordinate.row, column: coordinate.column)] else {
                continue
            }
            let currentLetter = letters[index]
            let allowsHighConfidenceDiacriticRepair = likelyConfusions(for: currentLetter)
                .contains { isDiacriticVariant(currentLetter, $0) }
            if cell.confidence >= 0.90 && !allowsHighConfidenceDiacriticRepair {
                continue
            }

            for replacement in replacementLetters(for: cell, current: letters[index]) {
                var repairedLetters = letters
                repairedLetters[index] = replacement
                let repairedWord = String(repairedLetters)
                guard dictionary.contains(repairedWord) else { continue }

                let repairedBoard = board.setCell(row: coordinate.row, column: coordinate.column, letter: replacement)
                let beforeInvalid = invalidWords(on: board).count
                let afterInvalid = invalidWords(on: repairedBoard).count
                let repair = BoardRepair(
                    row: coordinate.row,
                    column: coordinate.column,
                    originalLetter: letters[index],
                    repairedLetter: replacement,
                    reason: "dictionary: \(repairedWord)"
                )
                candidates.append(RepairCandidate(
                    board: repairedBoard,
                    repairs: [repair],
                    invalidWordReduction: beforeInvalid - afterInvalid,
                    score: scoreReplacement(cell: cell, replacement: replacement)
                ))
            }
        }

        return candidates
    }

    private func replacementLetters(for cell: CellRead, current: Character) -> [Character] {
        var replacements = cell.candidates
            .map(\.letter)
            .filter { $0 != current }

        for letter in likelyConfusions(for: current) where !replacements.contains(letter) {
            replacements.append(letter)
        }

        if let digit = cell.detectedScoreDigit {
            replacements = replacements.filter { letter in
                isDiacriticVariant(current, letter)
                    || likelyConfusions(for: current).contains(letter)
                    || letterValues[letter] == nil
                    || letterValues[letter] == digit
            }
        }

        return replacements
    }

    private func likelyConfusions(for letter: Character) -> [Character] {
        switch letter {
        case "N": ["H", "Ń"]
        case "H": ["N"]
        case "D": ["O", "B"]
        case "O": ["D", "C", "Ó"]
        case "C": ["O", "Ć"]
        case "B": ["D"]
        case "F": ["R"]
        case "R": ["F"]
        case "M": ["W"]
        case "W": ["M"]
        case "A": ["Ą"]
        case "Ą": ["A"]
        case "Ć": ["C"]
        case "E": ["Ę"]
        case "Ę": ["E"]
        case "L": ["Ł"]
        case "Ł": ["L"]
        case "Ń": ["N"]
        case "Ó": ["O"]
        case "S": ["Ś"]
        case "Ś": ["S"]
        case "Z": ["Ź", "Ż"]
        case "Ź": ["Z", "Ż"]
        case "Ż": ["Z", "Ź"]
        default: []
        }
    }

    private func isDiacriticVariant(_ lhs: Character, _ rhs: Character) -> Bool {
        func folded(_ letter: Character) -> String {
            String(letter)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
                .uppercased()
        }

        return lhs != rhs && folded(lhs) == folded(rhs)
    }

    private func scoreReplacement(cell: CellRead, replacement: Character) -> Double {
        var score = 1 - cell.confidence
        if let candidate = cell.candidates.first(where: { $0.letter == replacement }) {
            score += max(0, 1 - candidate.distance)
        }
        if let digit = cell.detectedScoreDigit, letterValues[replacement] == digit {
            score += 0.75
        }
        return score
    }

    private func affectedWords(on board: Board, row: Int, column: Int) -> [BoardWord] {
        BoardWordExtractor.extractWords(from: board).filter { word in
            word.coordinates.contains { $0.row == row && $0.column == column }
        }
    }

    private func isOccupied(_ board: Board, row: Int, column: Int) -> Bool {
        Board.isInside(row: row, column: column) && board[row, column].letter != nil
    }

    private static func key(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }
}

private struct RepairCandidate {
    let board: Board
    let repairs: [BoardRepair]
    let invalidWordReduction: Int
    let score: Double
}

private struct TileGlyphRecognizer {
    private static let maskSize = 32

    private let letterValues: [Character: Int]
    private let samples: [LetterSample]

    init(letterValues: [Character: Int]) throws {
        self.letterValues = letterValues
        self.samples = try Self.loadSamples(letterValues: letterValues)
    }

    private init(letterValues: [Character: Int], samples: [LetterSample]) {
        self.letterValues = letterValues
        self.samples = samples
    }

    func recognize(row: Int, column: Int, mapper: BoardImageMapper, sampler: BoardColorSampler) -> CellRead? {
        let bounds = mapper.cellBounds(row: row, column: column).insetBy(
            dx: mapper.cellBounds(row: row, column: column).width * 0.035,
            dy: mapper.cellBounds(row: row, column: column).height * 0.035
        )
        guard let shapeMask = extractShapeMask(sampler: sampler, bounds: bounds),
              let tileMask = extractTileMask(sampler: sampler, bounds: bounds) else {
            let digit = recognizeScoreDigit(sampler: sampler, bounds: bounds)
            return CellRead(row: row, column: column, letter: nil, confidence: 0, detectedScoreDigit: digit)
        }

        let digit = recognizeScoreDigit(sampler: sampler, bounds: bounds)
        let candidates = samples
            .map { sample -> (letter: Character, score: Double) in
                let score = similarity(shapeMask, sample.shapeMask) * 0.70
                    + similarity(tileMask, sample.tileMask) * 0.30
                return (sample.letter, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return String($0.letter) < String($1.letter)
            }

        guard let selected = selectCandidate(candidates, scoreDigit: digit) else {
            return CellRead(row: row, column: column, letter: nil, confidence: 0, detectedScoreDigit: digit)
        }

        let secondScore = candidates
            .filter { $0.letter != selected.letter }
            .map(\.score)
            .max() ?? 0
        let confidence = calculateConfidence(score: selected.score, secondScore: secondScore, scoreDigit: digit, letter: selected.letter)
        let publicCandidates = candidates.prefix(8).map {
            LetterCandidate(letter: $0.letter, distance: max(0, 1 - $0.score), matchedScoreDigit: digit)
        }

        return CellRead(
            row: row,
            column: column,
            letter: confidence < 0.10 ? nil : selected.letter,
            confidence: confidence,
            candidates: publicCandidates,
            detectedScoreDigit: digit
        )
    }

    private func selectCandidate(_ candidates: [(letter: Character, score: Double)], scoreDigit: Int?) -> (letter: Character, score: Double)? {
        guard let top = candidates.first else { return nil }
        guard let scoreDigit else { return top }
        if letterValues[top.letter] == scoreDigit {
            return top
        }

        guard let matched = candidates
            .filter({ letterValues[$0.letter] == scoreDigit })
            .max(by: { $0.score < $1.score }) else {
            return top
        }

        let threshold = isNhPair(top.letter, matched.letter) ? 0.82 : 0.88
        return matched.score >= top.score * threshold ? matched : top
    }

    private func calculateConfidence(score: Double, secondScore: Double, scoreDigit: Int?, letter: Character) -> Double {
        let margin = max(0, score - secondScore)
        var confidence = score * 0.75 + margin * 0.9
        if let scoreDigit {
            confidence += letterValues[letter] == scoreDigit ? 0.14 : -0.10
        }
        return min(1, max(0, confidence))
    }

    private func recognizeScoreDigit(sampler: BoardColorSampler, bounds: CGRect) -> Int? {
        let scoreBounds = CGRect(
            x: bounds.minX + bounds.width * 0.55,
            y: bounds.minY,
            width: max(1, bounds.width * 0.40),
            height: max(1, bounds.height * 0.32)
        )
        guard let mask = extractScoreMask(sampler: sampler, bounds: scoreBounds) else { return nil }
        return recognizeDigitByShape(mask)
    }

    private func recognizeDigitByShape(_ glyph: [Bool]) -> Int? {
        let points = glyphPoints(glyph)
        guard !points.isEmpty else { return nil }

        let width = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0) + 1
        let height = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0) + 1
        if width <= 12 && height >= 18 {
            return 1
        }

        let middle = density(glyph, y1: 12, y2: 19, x1: 5, x2: 27)
        let bottom = density(glyph, y1: 24, y2: 31, x1: 4, x2: 28)
        let lowerLeft = density(glyph, y1: 17, y2: 28, x1: 2, x2: 13)
        let lowerRight = density(glyph, y1: 17, y2: 28, x1: 19, x2: 30)
        let upperLeft = density(glyph, y1: 4, y2: 13, x1: 2, x2: 14)
        let upperRight = density(glyph, y1: 4, y2: 13, x1: 18, x2: 30)
        if middle >= 0.015,
           bottom >= 0.03,
           upperLeft + upperRight >= 0.32,
           lowerRight > lowerLeft + 0.01 || lowerLeft < 0.02 && lowerRight > 0.005 {
            return 3
        }

        return nil
    }

    private func extractShapeMask(sampler: BoardColorSampler, bounds: CGRect) -> [Bool]? {
        var pixels = extractForegroundPixels(sampler: sampler, bounds: bounds, includeLight: true)
        removeScoreDigitComponents(&pixels)
        let component = mainGlyphComponent(pixels)
        guard component.count >= 12 else { return nil }
        return normalize(component)
    }

    private func extractTileMask(sampler: BoardColorSampler, bounds: CGRect) -> [Bool]? {
        var mask = [Bool](repeating: false, count: Self.maskSize * Self.maskSize)
        var ink = 0
        for y in 0..<Self.maskSize {
            let sourceY = Int(bounds.minY + min(bounds.height - 1, (Double(y) + 0.5) * bounds.height / Double(Self.maskSize)))
            for x in 0..<Self.maskSize {
                let sourceX = Int(bounds.minX + min(bounds.width - 1, (Double(x) + 0.5) * bounds.width / Double(Self.maskSize)))
                guard let pixel = sampler.pixel(x: sourceX, y: sourceY), !isRedBadge(pixel) else { continue }
                let dark = isDarkGlyph(pixel)
                let light = pixel.red > 235 && pixel.green > 235 && pixel.blue > 235 && sampler.localOrangeBackgroundNear(x: sourceX, y: sourceY, bounds: bounds)
                if dark || light {
                    mask[y * Self.maskSize + x] = true
                    ink += 1
                }
            }
        }

        return ink < 12 ? nil : mask
    }

    private func extractScoreMask(sampler: BoardColorSampler, bounds: CGRect) -> [Bool]? {
        let pixels = extractForegroundPixels(sampler: sampler, bounds: bounds, includeLight: true)
        let component = scoreDigitComponent(pixels)
        return component.count < 3 ? nil : normalize(component)
    }

    private func extractForegroundPixels(sampler: BoardColorSampler, bounds: CGRect, includeLight: Bool) -> PixelMask {
        let minX = max(0, Int(bounds.minX))
        let maxX = min(sampler.width - 1, Int(bounds.maxX))
        let minY = max(0, Int(bounds.minY))
        let maxY = min(sampler.height - 1, Int(bounds.maxY))
        let width = max(1, maxX - minX + 1)
        let height = max(1, maxY - minY + 1)
        var values = [Bool](repeating: false, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let sourceX = minX + x
                let sourceY = minY + y
                guard let pixel = sampler.pixel(x: sourceX, y: sourceY), !isRedBadge(pixel) else { continue }
                let dark = isDarkGlyph(pixel)
                let light = includeLight && pixel.red > 235 && pixel.green > 235 && pixel.blue > 235 && sampler.localOrangeBackgroundNear(x: sourceX, y: sourceY, bounds: bounds)
                values[y * width + x] = dark || light
            }
        }

        return PixelMask(width: width, height: height, values: values)
    }

    private func removeScoreDigitComponents(_ pixels: inout PixelMask) {
        for component in connectedComponents(pixels) {
            let minX = component.map(\.x).min() ?? 0
            let maxX = component.map(\.x).max() ?? 0
            let minY = component.map(\.y).min() ?? 0
            let maxY = component.map(\.y).max() ?? 0
            let componentWidth = maxX - minX + 1
            let componentHeight = maxY - minY + 1
            let centerX = average(component.map(\.x))
            let centerY = average(component.map(\.y))
            let inScoreArea = centerX >= Double(pixels.width) * 0.55 && centerY <= Double(pixels.height) * 0.35
            let digitSized = Double(componentWidth) <= Double(pixels.width) * 0.28 && Double(componentHeight) <= Double(pixels.height) * 0.30
            guard inScoreArea && digitSized else { continue }
            for point in component {
                pixels.values[point.y * pixels.width + point.x] = false
            }
        }
    }

    private func scoreDigitComponent(_ pixels: PixelMask) -> [MaskPoint] {
        connectedComponents(pixels)
            .filter { $0.count >= 3 }
            .map { component -> (component: [MaskPoint], minX: Int, maxX: Int, minY: Int, maxY: Int, centerX: Double, centerY: Double) in
                (
                    component,
                    component.map(\.x).min() ?? 0,
                    component.map(\.x).max() ?? 0,
                    component.map(\.y).min() ?? 0,
                    component.map(\.y).max() ?? 0,
                    average(component.map(\.x)),
                    average(component.map(\.y))
                )
            }
            .filter {
                let componentWidth = $0.maxX - $0.minX + 1
                let componentHeight = $0.maxY - $0.minY + 1
                return $0.centerX >= Double(pixels.width) * 0.25
                    && $0.centerY <= Double(pixels.height) * 0.90
                    && Double(componentWidth) <= Double(pixels.width) * 0.75
                    && Double(componentHeight) <= Double(pixels.height) * 0.75
            }
            .sorted {
                if $0.centerX != $1.centerX { return $0.centerX > $1.centerX }
                if $0.centerY != $1.centerY { return $0.centerY < $1.centerY }
                return $0.component.count > $1.component.count
            }
            .first?.component ?? []
    }

    private func mainGlyphComponent(_ pixels: PixelMask) -> [MaskPoint] {
        let components = connectedComponents(pixels).sorted { $0.count > $1.count }
        guard let main = components.first else { return [] }
        let minX = main.map(\.x).min() ?? 0
        let maxX = main.map(\.x).max() ?? 0
        let minY = main.map(\.y).min() ?? 0
        let maxY = main.map(\.y).max() ?? 0
        let height = max(1, maxY - minY + 1)
        var points = main

        for component in components.dropFirst() where component.count >= 2 {
            let componentMinX = component.map(\.x).min() ?? 0
            let componentMaxX = component.map(\.x).max() ?? 0
            let componentMaxY = component.map(\.y).max() ?? 0
            let componentCenterX = average(component.map(\.x))
            let overlapsGlyph = componentMaxX >= minX - 4
                && componentMinX <= maxX + 4
                && componentCenterX >= Double(minX - 4)
                && componentCenterX <= Double(maxX + 4)
            let sitsAboveGlyph = Double(componentMaxY) <= Double(minY) + Double(height) * 0.38
            if overlapsGlyph && sitsAboveGlyph {
                points.append(contentsOf: component)
            }
        }

        return points
    }

    private func connectedComponents(_ pixels: PixelMask) -> [[MaskPoint]] {
        var visited = [Bool](repeating: false, count: pixels.width * pixels.height)
        var components: [[MaskPoint]] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let index = y * pixels.width + x
                guard pixels.values[index], !visited[index] else { continue }
                components.append(floodFill(pixels, visited: &visited, start: MaskPoint(x: x, y: y)))
            }
        }
        return components
    }

    private func floodFill(_ pixels: PixelMask, visited: inout [Bool], start: MaskPoint) -> [MaskPoint] {
        var queue = [start]
        var cursor = 0
        var component: [MaskPoint] = []
        visited[start.y * pixels.width + start.x] = true

        while cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            component.append(point)

            for direction in [MaskPoint(x: 1, y: 0), MaskPoint(x: -1, y: 0), MaskPoint(x: 0, y: 1), MaskPoint(x: 0, y: -1)] {
                let x = point.x + direction.x
                let y = point.y + direction.y
                guard x >= 0, y >= 0, x < pixels.width, y < pixels.height else { continue }
                let index = y * pixels.width + x
                guard pixels.values[index], !visited[index] else { continue }
                visited[index] = true
                queue.append(MaskPoint(x: x, y: y))
            }
        }

        return component
    }

    private func normalize(_ component: [MaskPoint]) -> [Bool] {
        let minX = component.map(\.x).min() ?? 0
        let maxX = component.map(\.x).max() ?? 0
        let minY = component.map(\.y).min() ?? 0
        let maxY = component.map(\.y).max() ?? 0
        let sourceWidth = max(1, maxX - minX + 1)
        let sourceHeight = max(1, maxY - minY + 1)
        let scale = min(Double(Self.maskSize - 4) / Double(sourceWidth), Double(Self.maskSize - 4) / Double(sourceHeight))
        let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))
        let offsetX = (Self.maskSize - targetWidth) / 2
        let offsetY = (Self.maskSize - targetHeight) / 2
        var normalized = [Bool](repeating: false, count: Self.maskSize * Self.maskSize)

        for point in component {
            let x = offsetX + Int((Double(point.x - minX) * scale).rounded())
            let y = offsetY + Int((Double(point.y - minY) * scale).rounded())
            if x >= 0, y >= 0, x < Self.maskSize, y < Self.maskSize {
                normalized[y * Self.maskSize + x] = true
            }
        }

        return normalized
    }

    private func similarity(_ glyph: [Bool], _ template: [Bool]) -> Double {
        var intersection = 0
        var glyphPixels = 0
        var templatePixels = 0
        for index in 0..<min(glyph.count, template.count) {
            if glyph[index] { glyphPixels += 1 }
            if template[index] { templatePixels += 1 }
            if glyph[index] && template[index] { intersection += 1 }
        }
        guard glyphPixels > 0, templatePixels > 0 else { return 0 }
        return Double(intersection) / sqrt(Double(glyphPixels * templatePixels))
    }

    private func density(_ glyph: [Bool], y1: Int, y2: Int, x1: Int, x2: Int) -> Double {
        var count = 0
        var total = 0
        for y in max(0, y1)...min(Self.maskSize - 1, y2) {
            for x in max(0, x1)...min(Self.maskSize - 1, x2) {
                total += 1
                if glyph[y * Self.maskSize + x] { count += 1 }
            }
        }
        return total == 0 ? 0 : Double(count) / Double(total)
    }

    private func glyphPoints(_ glyph: [Bool]) -> [MaskPoint] {
        var points: [MaskPoint] = []
        for y in 0..<Self.maskSize {
            for x in 0..<Self.maskSize where glyph[y * Self.maskSize + x] {
                points.append(MaskPoint(x: x, y: y))
            }
        }
        return points
    }

    private func isNhPair(_ lhs: Character, _ rhs: Character) -> Bool {
        lhs != rhs && (lhs == "N" || lhs == "H") && (rhs == "N" || rhs == "H")
    }

    private func isRedBadge(_ pixel: RGBPixel) -> Bool {
        pixel.red > 180 && pixel.green < 95 && pixel.blue < 95 && Double(pixel.red) > Double(pixel.green) * 1.8
    }

    private func isDarkGlyph(_ pixel: RGBPixel) -> Bool {
        let maxValue = max(pixel.red, max(pixel.green, pixel.blue))
        let minValue = min(pixel.red, min(pixel.green, pixel.blue))
        return maxValue < 190 && maxValue - minValue < 90
    }

    private func average(_ values: [Int]) -> Double {
        values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func loadSamples(letterValues: [Character: Int]) throws -> [LetterSample] {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "Data/letters-samples") else {
            return []
        }

        let rawSamples = urls.compactMap { url -> (letter: Character, image: CGImage)? in
            let name = url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
            guard name.count == 1,
                  let letter = name.first,
                  PolishAlphabet.isPolishLetter(letter),
                  letterValues[PolishAlphabet.normalizeLetter(letter)] != nil,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return (PolishAlphabet.normalizeLetter(letter), image)
        }

        let extractor = TileGlyphRecognizer(letterValues: letterValues, samples: [])
        return rawSamples.compactMap { sample in
            let mapper = BoardImageMapper(width: sample.image.width, height: sample.image.height, boardX: 0, boardY: 0, boardSize: Double(min(sample.image.width, sample.image.height)))
            let sampler = BoardColorSampler(image: sample.image, mapper: mapper)
            let bounds = CGRect(x: 0, y: 0, width: sample.image.width, height: sample.image.height).insetBy(
                dx: Double(sample.image.width) * 0.035,
                dy: Double(sample.image.height) * 0.035
            )
            guard let shapeMask = extractor.extractShapeMask(sampler: sampler, bounds: bounds),
                  let tileMask = extractor.extractTileMask(sampler: sampler, bounds: bounds) else {
                return nil
            }
            return LetterSample(letter: sample.letter, shapeMask: shapeMask, tileMask: tileMask)
        }.sorted { String($0.letter) < String($1.letter) }
    }
}

private struct LetterSample {
    let letter: Character
    let shapeMask: [Bool]
    let tileMask: [Bool]
}

private struct PixelMask {
    let width: Int
    let height: Int
    var values: [Bool]
}

private struct MaskPoint {
    let x: Int
    let y: Int
}

private struct RGBPixel {
    let red: Int
    let green: Int
    let blue: Int
}

private struct BoardImageMapper {
    let width: Int
    let height: Int
    let boardX: Double
    let boardY: Double
    let boardSize: Double

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.boardSize = Double(min(width, height))
        self.boardX = (Double(width) - boardSize) / 2
        self.boardY = (Double(height) - boardSize) / 2
    }

    init(width: Int, height: Int, boardX: Double, boardY: Double, boardSize: Double) {
        self.width = width
        self.height = height
        self.boardX = boardX
        self.boardY = boardY
        self.boardSize = boardSize
    }

    func coordinate(for normalizedBoundingBox: CGRect) -> (row: Int, column: Int)? {
        let x = Double(normalizedBoundingBox.midX) * Double(width)
        let y = (1 - Double(normalizedBoundingBox.midY)) * Double(height)
        guard x >= boardX, x < boardX + boardSize, y >= boardY, y < boardY + boardSize else {
            return nil
        }

        let cellSize = boardSize / Double(Board.size)
        let column = Int((x - boardX) / cellSize)
        let row = Int((y - boardY) / cellSize)
        guard Board.isInside(row: row, column: column) else { return nil }
        return (row, column)
    }

    func sampleRect(row: Int, column: Int) -> CGRect {
        cellBounds(row: row, column: column).insetBy(
            dx: boardSize / Double(Board.size) * 0.2,
            dy: boardSize / Double(Board.size) * 0.2
        )
    }

    func cellBounds(row: Int, column: Int) -> CGRect {
        let cellSize = boardSize / Double(Board.size)
        return CGRect(
            x: boardX + Double(column) * cellSize,
            y: boardY + Double(row) * cellSize,
            width: cellSize,
            height: cellSize
        )
    }
}

private final class BoardColorSampler {
    let width: Int
    let height: Int
    private let pixels: [UInt8]
    private let bytesPerRow: Int
    private let mapper: BoardImageMapper

    init(image: CGImage, mapper: BoardImageMapper) {
        let imageWidth = image.width
        let imageHeight = image.height
        self.width = imageWidth
        self.height = imageHeight
        self.mapper = mapper

        let bytesPerPixel = 4
        let rowBytes = imageWidth * bytesPerPixel
        self.bytesPerRow = rowBytes
        var data = [UInt8](repeating: 0, count: imageHeight * rowBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { buffer in
            if let context = CGContext(
                data: buffer.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            }
        }
        self.pixels = data
    }

    func cellLooksOccupied(row: Int, column: Int) -> Bool {
        let rect = mapper.sampleRect(row: row, column: column)
        var orangePixels = 0
        var sampledPixels = 0

        let minX = max(0, Int(rect.minX))
        let maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height - 1, Int(rect.maxY))
        let step = max(1, min(maxX - minX + 1, maxY - minY + 1) / 12)

        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let offset = y * bytesPerRow + x * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                sampledPixels += 1
                if red >= 190 && green >= 120 && green <= 210 && blue <= 130 && red > blue + 70 {
                    orangePixels += 1
                }
                x += step
            }
            y += step
        }

        guard sampledPixels > 0 else { return false }
        return Double(orangePixels) / Double(sampledPixels) > 0.35
    }

    func pixel(x: Int, y: Int) -> RGBPixel? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = y * bytesPerRow + x * 4
        return RGBPixel(
            red: Int(pixels[offset]),
            green: Int(pixels[offset + 1]),
            blue: Int(pixels[offset + 2])
        )
    }

    func localOrangeBackgroundNear(x: Int, y: Int, bounds: CGRect) -> Bool {
        let radius = max(2, Int(min(bounds.width, bounds.height)) / 8)
        let left = max(0, Int(bounds.minX))
        let right = min(width - 1, Int(bounds.maxX))
        let top = max(0, Int(bounds.minY))
        let bottom = min(height - 1, Int(bounds.maxY))
        for yy in max(top, y - radius)...min(bottom, y + radius) {
            for xx in max(left, x - radius)...min(right, x + radius) {
                guard let pixel = pixel(x: xx, y: yy) else { continue }
                if pixel.red > 190 && pixel.green >= 120 && pixel.green <= 210 && pixel.blue < 130 {
                    return true
                }
            }
        }
        return false
    }
}

private extension String {
    var characterRanges: [Range<String.Index>] {
        indices.map { index in
            index..<self.index(after: index)
        }
    }
}
