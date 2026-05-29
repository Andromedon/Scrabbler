import Foundation

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
    case notYetPorted

    public var errorDescription: String? {
        "Native OCR is scaffolded for the Swift port, but the pixel recognizer has not been ported in this phase yet."
    }
}

public struct NativeBoardImageReader: BoardImageReading {
    public init() {}

    public func readBoard(from imageURL: URL, bonuses: [[BonusType]]) async throws -> BoardReadResult {
        _ = imageURL
        throw BoardImageReaderError.notYetPorted
    }
}

public struct DictionaryBoardRepairer: Sendable {
    private let dictionary: WordDictionary

    public init(dictionary: WordDictionary) {
        self.dictionary = dictionary
    }

    public func invalidWords(on board: Board) -> [BoardWord] {
        BoardWordExtractor.extractWords(from: board).filter { !dictionary.contains($0.text) }
    }
}
