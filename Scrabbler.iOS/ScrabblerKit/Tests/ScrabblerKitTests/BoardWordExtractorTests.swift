import Testing
@testable import ScrabblerKit

@Suite("Board word extractor")
struct BoardWordExtractorTests {
    @Test func extractsHorizontalAndVerticalWordsWithCoordinates() {
        let board = emptyBoard()
            .setCell(row: 0, column: 0, letter: "A")
            .setCell(row: 0, column: 1, letter: "L")
            .setCell(row: 0, column: 2, letter: "A")
            .setCell(row: 1, column: 0, letter: "S")
            .setCell(row: 2, column: 0, letter: "A")

        let words = BoardWordExtractor.extractWords(from: board)

        #expect(words.contains { $0.text == "ALA" && $0.direction == .horizontal && $0.coordinates.map(\.column) == [0, 1, 2] })
        #expect(words.contains { $0.text == "ASA" && $0.direction == .vertical && $0.coordinates.map(\.row) == [0, 1, 2] })
    }

    @Test func ignoresSingleLetterRuns() {
        let board = emptyBoard().setCell(row: 0, column: 0, letter: "A")

        #expect(BoardWordExtractor.extractWords(from: board).isEmpty)
    }

    private func emptyBoard() -> Board {
        Board(bonuses: Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size))
    }
}
