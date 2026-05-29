import Foundation

public struct PlacedTile: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let letter: Character
    public let isBlank: Bool

    public init(row: Int, column: Int, letter: Character, isBlank: Bool) {
        self.row = row
        self.column = column
        self.letter = letter
        self.isBlank = isBlank
    }
}

public struct Move: Equatable, Sendable {
    public let word: String
    public let row: Int
    public let column: Int
    public let direction: Direction
    public let placedTiles: [PlacedTile]
    public let score: Int
    public let crossWords: [String]
}

public protocol MoveSolving: Sendable {
    func findBestMoves(board: Board, rack: Rack, limit: Int) throws -> [Move]
}

public final class MoveSolver: MoveSolving, @unchecked Sendable {
    public static let rackBingoBonus = 25
    private static let directions: [Direction] = [.horizontal, .vertical]
    private static let alphabetIndexes = Dictionary(uniqueKeysWithValues: PolishAlphabet.letters.enumerated().map { ($0.element, $0.offset) })

    private let dictionary: WordDictionary
    private let letterValues: [Character: Int]

    public init(dictionary: WordDictionary, letterValues: [Character: Int]) {
        self.dictionary = dictionary
        self.letterValues = letterValues
    }

    public func findBestMoves(board: Board, rack: Rack, limit: Int) throws -> [Move] {
        guard limit > 0 else { return [] }

        let context = SolverContext(board: board, rack: rack)
        var bestMoves: [Move] = []

        for (length, words) in dictionary.wordsByLength where length <= Board.size {
            for word in words {
                if !couldBeMadeFromRackAndBoard(word, rackLetters: context.rackLetterCounts, blankCount: rack.blankCount, boardLetters: context.boardLetterCounts) {
                    continue
                }

                for direction in Self.directions {
                    let maxStart = Board.size - word.count
                    for fixedAxis in 0..<Board.size {
                        for start in 0...maxStart {
                            if let move = try tryBuildMove(context: context, word: word, direction: direction, fixedAxis: fixedAxis, start: start) {
                                insertCandidate(move, into: &bestMoves, limit: limit)
                            }
                        }
                    }
                }
            }
        }

        return bestMoves
    }

    private func insertCandidate(_ candidate: Move, into bestMoves: inout [Move], limit: Int) {
        var index = 0
        while index < bestMoves.count && compare(bestMoves[index], candidate) <= 0 {
            index += 1
        }

        guard index < limit else { return }
        bestMoves.insert(candidate, at: index)
        if bestMoves.count > limit {
            bestMoves.removeLast()
        }
    }

    private func couldBeMadeFromRackAndBoard(_ word: String, rackLetters: [Int], blankCount: Int, boardLetters: [Int]) -> Bool {
        var wordCounts = Array(repeating: 0, count: Self.alphabetIndexes.count)
        for letter in word {
            guard let index = Self.alphabetIndexes[letter] else { return false }
            wordCounts[index] += 1
        }

        var blanksNeeded = 0
        for index in wordCounts.indices {
            let missing = wordCounts[index] - rackLetters[index] - boardLetters[index]
            if missing > 0 {
                blanksNeeded += missing
                if blanksNeeded > blankCount {
                    return false
                }
            }
        }
        return true
    }

    private func tryBuildMove(context: SolverContext, word: String, direction: Direction, fixedAxis: Int, start: Int) throws -> Move? {
        let row = direction == .horizontal ? fixedAxis : start
        let column = direction == .horizontal ? start : fixedAxis
        if hasAdjacentBeforeOrAfter(context.occupied, length: word.count, row: row, column: column, direction: direction) {
            return nil
        }

        var remaining = context.rackLetterCounts
        var placed: [PlacementCandidate] = []
        var blanks = context.rack.blankCount
        var touchedExisting = false
        var touchedNeighbor = false
        var score = 0
        var mainWordMultiplier = 1
        let letters = Array(word)

        for index in letters.indices {
            let coordinate = coordinate(row: row, column: column, direction: direction, offset: index)
            let cell = context.board[coordinate.row, coordinate.column]
            let letter = letters[index]

            if let existing = cell.letter {
                if existing != letter { return nil }
                touchedExisting = true
                score += try letterScore(letter, isBlank: cell.isBlank)
                continue
            }

            guard let letterIndex = Self.alphabetIndexes[letter] else { return nil }
            if remaining[letterIndex] > 0 {
                remaining[letterIndex] -= 1
                placed.append(PlacementCandidate(row: coordinate.row, column: coordinate.column, letter: letter, isBlank: false))
                score += try letterScore(letter, isBlank: false) * letterMultiplier(cell.bonus)
            } else if blanks > 0 {
                blanks -= 1
                placed.append(PlacementCandidate(row: coordinate.row, column: coordinate.column, letter: letter, isBlank: true))
                score += try letterScore(letter, isBlank: true) * letterMultiplier(cell.bonus)
            } else {
                return nil
            }

            mainWordMultiplier *= wordMultiplier(cell.bonus)
            touchedNeighbor = touchedNeighbor || context.hasNeighbor[coordinate.row][coordinate.column]
        }

        guard !placed.isEmpty else { return nil }
        if context.isBoardEmpty {
            guard coversCenter(row: row, column: column, direction: direction, length: word.count) else { return nil }
        } else if !touchedExisting && !touchedNeighbor {
            return nil
        }

        score *= mainWordMultiplier
        var crossWords: [String] = []
        for tile in placed {
            let crossDirection: Direction = direction == .horizontal ? .vertical : .horizontal
            guard let result = try scoreCrossWord(board: context.board, newTile: tile, direction: crossDirection) else {
                return nil
            }
            if let crossWord = result.word {
                crossWords.append(crossWord)
                score += result.score
            }
        }

        if placed.count == 7 {
            score += Self.rackBingoBonus
        }

        return Move(
            word: word,
            row: row,
            column: column,
            direction: direction,
            placedTiles: placed.map { PlacedTile(row: $0.row, column: $0.column, letter: $0.letter, isBlank: $0.isBlank) },
            score: score,
            crossWords: crossWords
        )
    }

    private func scoreCrossWord(board: Board, newTile: PlacementCandidate, direction: Direction) throws -> (word: String?, score: Int)? {
        var startRow = newTile.row
        var startColumn = newTile.column

        while true {
            let previous = direction == .horizontal ? (startRow, startColumn - 1) : (startRow - 1, startColumn)
            if !isOccupied(board: board, row: previous.0, column: previous.1) {
                break
            }
            startRow = previous.0
            startColumn = previous.1
        }

        var word = ""
        var currentRow = startRow
        var currentColumn = startColumn
        var multiplier = 1
        var wordScore = 0

        while Board.isInside(row: currentRow, column: currentColumn) {
            let isNewTile = currentRow == newTile.row && currentColumn == newTile.column
            let letter = isNewTile ? newTile.letter : board[currentRow, currentColumn].letter
            guard let letter else { break }

            word.append(letter)
            let cell = board[currentRow, currentColumn]
            if isNewTile {
                wordScore += try letterScore(letter, isBlank: newTile.isBlank) * letterMultiplier(cell.bonus)
                multiplier *= wordMultiplier(cell.bonus)
            } else {
                wordScore += try letterScore(letter, isBlank: cell.isBlank)
            }

            if direction == .horizontal {
                currentColumn += 1
            } else {
                currentRow += 1
            }
        }

        if word.count <= 1 {
            return (nil, 0)
        }

        guard dictionary.contains(word) else {
            return nil
        }

        return (word, wordScore * multiplier)
    }

    private func letterScore(_ letter: Character, isBlank: Bool) throws -> Int {
        if isBlank { return 0 }
        guard let value = letterValues[letter] else {
            throw ScrabblerError.missingLetterValue(letter)
        }
        return value
    }

    private func letterMultiplier(_ bonus: BonusType) -> Int {
        switch bonus {
        case .doubleLetter: 2
        case .tripleLetter: 3
        default: 1
        }
    }

    private func wordMultiplier(_ bonus: BonusType) -> Int {
        switch bonus {
        case .doubleWord: 2
        case .tripleWord: 3
        default: 1
        }
    }

    private func coordinate(row: Int, column: Int, direction: Direction, offset: Int) -> (row: Int, column: Int) {
        direction == .horizontal ? (row, column + offset) : (row + offset, column)
    }

    private func hasAdjacentBeforeOrAfter(_ occupied: [[Bool]], length: Int, row: Int, column: Int, direction: Direction) -> Bool {
        let before = direction == .horizontal ? (row, column - 1) : (row - 1, column)
        let after = direction == .horizontal ? (row, column + length) : (row + length, column)
        return isOccupied(occupied: occupied, row: before.0, column: before.1) ||
            isOccupied(occupied: occupied, row: after.0, column: after.1)
    }

    private func coversCenter(row: Int, column: Int, direction: Direction, length: Int) -> Bool {
        for offset in 0..<length {
            let value = coordinate(row: row, column: column, direction: direction, offset: offset)
            if value.row == 7 && value.column == 7 {
                return true
            }
        }
        return false
    }

    private func isOccupied(board: Board, row: Int, column: Int) -> Bool {
        Board.isInside(row: row, column: column) && board[row, column].letter != nil
    }

    private func isOccupied(occupied: [[Bool]], row: Int, column: Int) -> Bool {
        Board.isInside(row: row, column: column) && occupied[row][column]
    }

    private func compare(_ x: Move, _ y: Move) -> Int {
        if x.score != y.score { return y.score - x.score }
        let blankDiff = blankTileCount(x) - blankTileCount(y)
        if blankDiff != 0 { return blankDiff }
        if x.word.count != y.word.count { return y.word.count - x.word.count }
        if x.word != y.word { return x.word < y.word ? -1 : 1 }
        if x.row != y.row { return x.row - y.row }
        return x.column - y.column
    }

    private func blankTileCount(_ move: Move) -> Int {
        move.placedTiles.filter(\.isBlank).count
    }
}

private struct PlacementCandidate {
    let row: Int
    let column: Int
    let letter: Character
    let isBlank: Bool
}

private struct SolverContext {
    let board: Board
    let rack: Rack
    let isBoardEmpty: Bool
    let occupied: [[Bool]]
    let hasNeighbor: [[Bool]]
    let boardLetterCounts: [Int]
    let rackLetterCounts: [Int]

    init(board: Board, rack: Rack) {
        self.board = board
        self.rack = rack
        var occupied = Array(repeating: Array(repeating: false, count: Board.size), count: Board.size)
        var hasNeighbor = Array(repeating: Array(repeating: false, count: Board.size), count: Board.size)
        var boardLetterCounts = Array(repeating: 0, count: PolishAlphabet.letters.count)
        var rackLetterCounts = Array(repeating: 0, count: PolishAlphabet.letters.count)
        var isBoardEmpty = true

        let alphabetIndexes = Dictionary(uniqueKeysWithValues: PolishAlphabet.letters.enumerated().map { ($0.element, $0.offset) })
        for (letter, count) in rack.letters {
            if let index = alphabetIndexes[letter] {
                rackLetterCounts[index] = count
            }
        }

        for row in 0..<Board.size {
            for column in 0..<Board.size {
                guard let letter = board[row, column].letter else { continue }
                isBoardEmpty = false
                occupied[row][column] = true
                if let index = alphabetIndexes[letter] {
                    boardLetterCounts[index] += 1
                }
            }
        }

        if !isBoardEmpty {
            for row in 0..<Board.size {
                for column in 0..<Board.size where !occupied[row][column] {
                    hasNeighbor[row][column] =
                        Self.isOccupied(occupied, row: row - 1, column: column) ||
                        Self.isOccupied(occupied, row: row + 1, column: column) ||
                        Self.isOccupied(occupied, row: row, column: column - 1) ||
                        Self.isOccupied(occupied, row: row, column: column + 1)
                }
            }
        }

        self.isBoardEmpty = isBoardEmpty
        self.occupied = occupied
        self.hasNeighbor = hasNeighbor
        self.boardLetterCounts = boardLetterCounts
        self.rackLetterCounts = rackLetterCounts
    }

    private static func isOccupied(_ occupied: [[Bool]], row: Int, column: Int) -> Bool {
        Board.isInside(row: row, column: column) && occupied[row][column]
    }
}
