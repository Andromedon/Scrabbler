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
    public let repairedLetter: Character
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
    public init() {}

    public func readBoard(from imageURL: URL, bonuses: [[BonusType]]) async throws -> BoardReadResult {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BoardImageReaderError.imageCouldNotBeLoaded
        }

        let observations = try recognizeText(in: imageURL)
        let mapper = BoardImageMapper(width: image.width, height: image.height)
        let sampler = BoardColorSampler(image: image, mapper: mapper)

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
                guard readsByCell[key] == nil,
                      sampler.cellLooksOccupied(row: row, column: column) else {
                    continue
                }

                readsByCell[key] = CellRead(
                    row: row,
                    column: column,
                    letter: nil,
                    confidence: 0
                )
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
            guard let repair = bestRepair(on: board, invalidWords: invalidWords, cellsByKey: cellsByKey) else {
                break
            }

            board = board.setCell(row: repair.row, column: repair.column, letter: repair.repairedLetter)
            repairs.append(repair)
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

    private func bestRepair(on board: Board, invalidWords: [BoardWord], cellsByKey: [String: CellRead]) -> BoardRepair? {
        let rawCandidates = (invalidWords
            .flatMap { repairCandidates(for: $0, on: board, cellsByKey: cellsByKey) }
            + gapRepairCandidates(on: board, cellsByKey: cellsByKey))
            .filter { candidate in
                affectedWords(on: candidate.board, row: candidate.repair.row, column: candidate.repair.column)
                    .allSatisfy { dictionary.contains($0.text) }
            }

        var deduplicated: [String: RepairCandidate] = [:]
        for candidate in rawCandidates {
            let key = "\(candidate.repair.row):\(candidate.repair.column):\(candidate.repair.originalLetter.map(String.init) ?? "."):\(candidate.repair.repairedLetter)"
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

        return best.repair
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
              cells.count > 2,
              let words = dictionary.wordsByLength[cells.count] else {
            return nil
        }

        let beforeInvalid = invalidWords(on: board).count
        let matches = words
            .compactMap { word in
                buildGapCandidate(
                    on: board,
                    cells: cells,
                    word: word,
                    gapRow: row,
                    gapColumn: column,
                    cellsByKey: cellsByKey,
                    beforeInvalid: beforeInvalid
                )
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

    private func buildGapCandidate(
        on board: Board,
        cells: [(row: Int, column: Int, letter: Character?)],
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
            repair: repairs[0],
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
                    repair: repair,
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
            replacements = replacements.filter { letterValues[$0] == nil || letterValues[$0] == digit }
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
    let repair: BoardRepair
    let invalidWordReduction: Int
    let score: Double
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
        let cellSize = boardSize / Double(Board.size)
        let inset = cellSize * 0.2
        return CGRect(
            x: boardX + Double(column) * cellSize + inset,
            y: boardY + Double(row) * cellSize + inset,
            width: cellSize - inset * 2,
            height: cellSize - inset * 2
        )
    }
}

private final class BoardColorSampler {
    private let width: Int
    private let height: Int
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
}

private extension String {
    var characterRanges: [Range<String.Index>] {
        indices.map { index in
            index..<self.index(after: index)
        }
    }
}
