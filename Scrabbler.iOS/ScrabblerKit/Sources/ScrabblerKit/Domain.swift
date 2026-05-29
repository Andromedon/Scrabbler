import Foundation

public enum BonusType: String, CaseIterable, Sendable {
    case none = "None"
    case doubleLetter = "DoubleLetter"
    case tripleLetter = "TripleLetter"
    case doubleWord = "DoubleWord"
    case tripleWord = "TripleWord"
}

public enum Direction: String, Sendable {
    case horizontal
    case vertical
}

public enum PolishAlphabet {
    public static let letters = Array("AĄBCĆDEĘFGHIJKLŁMNŃOÓPRSŚTUWYZŹŻ")
    public static let letterSet = Set(letters)

    public static func normalizeLetter(_ letter: Character) -> Character {
        Character(String(letter).uppercased(with: Locale(identifier: "pl_PL")))
    }

    public static func normalizeWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
            .map { String(normalizeLetter($0)) }
            .joined()
    }

    public static func isPolishLetter(_ letter: Character) -> Bool {
        letterSet.contains(normalizeLetter(letter))
    }
}

public struct BoardCell: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let letter: Character?
    public let isBlank: Bool
    public let bonus: BonusType

    public var isEmpty: Bool { letter == nil }

    public init(row: Int, column: Int, letter: Character?, isBlank: Bool, bonus: BonusType) {
        self.row = row
        self.column = column
        self.letter = letter.map(PolishAlphabet.normalizeLetter)
        self.isBlank = letter != nil && isBlank
        self.bonus = bonus
    }

    public func withLetter(_ letter: Character?, isBlank: Bool = false) -> BoardCell {
        BoardCell(row: row, column: column, letter: letter, isBlank: isBlank, bonus: bonus)
    }
}

public struct Board: Equatable, Sendable {
    public static let size = 15
    private var cells: [[BoardCell]]

    public init(bonuses: [[BonusType]]) {
        precondition(bonuses.count == Board.size && bonuses.allSatisfy { $0.count == Board.size }, "Bonus matrix must be 15x15.")
        self.cells = (0..<Board.size).map { row in
            (0..<Board.size).map { column in
                BoardCell(row: row, column: column, letter: nil, isBlank: false, bonus: bonuses[row][column])
            }
        }
    }

    private init(cells: [[BoardCell]]) {
        self.cells = cells
    }

    public subscript(row: Int, column: Int) -> BoardCell {
        cells[row][column]
    }

    public var allCells: [BoardCell] {
        cells.flatMap { $0 }
    }

    public var isEmpty: Bool {
        allCells.allSatisfy(\.isEmpty)
    }

    public func setCell(row: Int, column: Int, letter: Character?, isBlank: Bool = false) -> Board {
        guard Board.isInside(row: row, column: column) else {
            preconditionFailure("Cell is outside the 15x15 board.")
        }

        var copy = cells
        copy[row][column] = copy[row][column].withLetter(letter, isBlank: isBlank)
        return Board(cells: copy)
    }

    public static func isInside(row: Int, column: Int) -> Bool {
        row >= 0 && row < size && column >= 0 && column < size
    }

    public func render() -> String {
        var output = "    A B C D E F G H I J K L M N O\n"
        for row in 0..<Board.size {
            output += String(format: "%2d  ", row + 1)
            for column in 0..<Board.size {
                output += String(cells[row][column].letter ?? ".")
                output += " "
            }
            output += "\n"
        }
        return output
    }
}

public struct Rack: Equatable, Sendable {
    public let letters: [Character: Int]
    public let blankCount: Int

    public init(letters: [Character], blanks: Int) {
        var counts: [Character: Int] = [:]
        for letter in letters.map(PolishAlphabet.normalizeLetter) {
            counts[letter, default: 0] += 1
        }
        self.letters = counts
        self.blankCount = blanks
    }

    public static func parse(_ input: String) throws -> Rack {
        var letters: [Character] = []
        var blanks = 0
        for raw in input where !raw.isWhitespace {
            if raw == "?" {
                blanks += 1
                continue
            }

            let letter = PolishAlphabet.normalizeLetter(raw)
            guard PolishAlphabet.isPolishLetter(letter) else {
                throw ScrabblerError.invalidRackLetter(String(raw))
            }
            letters.append(letter)
        }
        return Rack(letters: letters, blanks: blanks)
    }
}

public enum ScrabblerError: LocalizedError, Equatable {
    case invalidRackLetter(String)
    case invalidCorrection(String)
    case invalidCoordinate(String)
    case coordinateOutsideBoard(String)
    case invalidCorrectionLetter(String)
    case missingLetterValue(Character)
    case dictionaryNotFound(String)
    case emptyDictionary

    public var errorDescription: String? {
        switch self {
        case .invalidRackLetter(let letter): "Unsupported rack letter: \(letter)"
        case .invalidCorrection(let correction): "Invalid correction: \(correction)"
        case .invalidCoordinate(let value): "Invalid coordinate: \(value)"
        case .coordinateOutsideBoard(let value): "Coordinate outside board: \(value)"
        case .invalidCorrectionLetter(let value): "Invalid correction letter: \(value)"
        case .missingLetterValue(let letter): "Missing value for letter '\(letter)'."
        case .dictionaryNotFound(let path): "Dictionary file was not found: \(path)"
        case .emptyDictionary: "Dictionary did not contain any valid Polish words with length 2..15."
        }
    }
}

public enum BoardCorrectionParser {
    public static func applyCorrections(to board: Board, input: String) throws -> Board {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return board
        }

        var current = board
        for item in input.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !item.isEmpty {
            current = try applyCorrection(to: current, correction: item)
        }
        return current
    }

    public static func applyCorrection(to board: Board, correction: String) throws -> Board {
        let parts = correction.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else {
            throw ScrabblerError.invalidCorrection(correction)
        }

        let coordinate = try parseCoordinate(parts[0])
        let value = parts[1]
        if value == "." || value == "?" {
            return board.setCell(row: coordinate.row, column: coordinate.column, letter: nil)
        }

        let isBlank = value.hasSuffix("?")
        let letterText = isBlank ? String(value.dropLast()) : value
        guard letterText.count == 1, let letter = letterText.first, PolishAlphabet.isPolishLetter(letter) else {
            throw ScrabblerError.invalidCorrectionLetter(value)
        }

        return board.setCell(row: coordinate.row, column: coordinate.column, letter: letter, isBlank: isBlank)
    }

    public static func parseCoordinate(_ value: String) throws -> (row: Int, column: Int) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count >= 2, let columnLetter = normalized.first else {
            throw ScrabblerError.invalidCoordinate(value)
        }

        let columns = Array("ABCDEFGHIJKLMNO")
        guard let column = columns.firstIndex(of: columnLetter),
              let rowNumber = Int(normalized.dropFirst()) else {
            throw ScrabblerError.invalidCoordinate(value)
        }

        let row = rowNumber - 1
        guard Board.isInside(row: row, column: column) else {
            throw ScrabblerError.coordinateOutsideBoard(value)
        }
        return (row, column)
    }
}

public struct BoardWord: Equatable, Sendable {
    public let text: String
    public let direction: Direction
    public let coordinates: [(row: Int, column: Int)]

    public static func == (lhs: BoardWord, rhs: BoardWord) -> Bool {
        lhs.text == rhs.text && lhs.direction == rhs.direction &&
            lhs.coordinates.map { [$0.row, $0.column] } == rhs.coordinates.map { [$0.row, $0.column] }
    }
}

public enum BoardWordExtractor {
    public static func extractWords(from board: Board) -> [BoardWord] {
        extract(from: board, direction: .horizontal) + extract(from: board, direction: .vertical)
    }

    private static func extract(from board: Board, direction: Direction) -> [BoardWord] {
        var words: [BoardWord] = []
        for fixed in 0..<Board.size {
            var currentLetters = ""
            var coordinates: [(row: Int, column: Int)] = []
            for offset in 0..<Board.size {
                let row = direction == .horizontal ? fixed : offset
                let column = direction == .horizontal ? offset : fixed
                if let letter = board[row, column].letter {
                    currentLetters.append(letter)
                    coordinates.append((row, column))
                } else {
                    appendIfWord(&words, currentLetters, direction, coordinates)
                    currentLetters = ""
                    coordinates = []
                }
            }
            appendIfWord(&words, currentLetters, direction, coordinates)
        }
        return words
    }

    private static func appendIfWord(_ words: inout [BoardWord], _ text: String, _ direction: Direction, _ coordinates: [(row: Int, column: Int)]) {
        if text.count > 1 {
            words.append(BoardWord(text: text, direction: direction, coordinates: coordinates))
        }
    }
}
