import Testing
@testable import ScrabblerKit

@Suite("Board correction parser")
struct BoardCorrectionParserTests {
    @Test func appliesLetterCorrection() throws {
        let board = try BoardCorrectionParser.applyCorrections(to: emptyBoard(), input: "A1=Ł")

        #expect(board[0, 0].letter == "Ł")
        #expect(!board[0, 0].isBlank)
    }

    @Test func appliesBlankCorrection() throws {
        let board = try BoardCorrectionParser.applyCorrections(to: emptyBoard(), input: "H8=Ż?")

        #expect(board[7, 7].letter == "Ż")
        #expect(board[7, 7].isBlank)
    }

    @Test func clearsCellWithDotOrQuestionMark() throws {
        let board = emptyBoard().setCell(row: 9, column: 9, letter: "A")

        #expect(try BoardCorrectionParser.applyCorrections(to: board, input: "J10=.")[9, 9].letter == nil)
        #expect(try BoardCorrectionParser.applyCorrections(to: board, input: "J10=?")[9, 9].letter == nil)
    }

    @Test func appliesCommaSeparatedCorrections() throws {
        let board = try BoardCorrectionParser.applyCorrections(to: emptyBoard(), input: "A1=Ł, H8=?, J10=Ń")

        #expect(board[0, 0].letter == "Ł")
        #expect(board[7, 7].letter == nil)
        #expect(board[9, 9].letter == "Ń")
    }

    @Test func formatsCorrectionEntriesAndAppendsThem() {
        #expect(BoardCorrectionParser.correctionEntry(row: 0, column: 0) == "A1=")
        #expect(BoardCorrectionParser.correctionEntry(row: 7, column: 7) == "H8=")

        #expect(
            BoardCorrectionParser.appendCorrectionEntries(
                to: "",
                coordinates: [(row: 0, column: 0), (row: 7, column: 7)]
            ) == "A1=, H8="
        )
        #expect(
            BoardCorrectionParser.appendCorrectionEntries(
                to: "B2=A",
                coordinates: [(row: 9, column: 9)]
            ) == "B2=A, J10="
        )
        #expect(
            BoardCorrectionParser.appendCorrectionEntries(
                to: "B2=A",
                coordinates: []
            ) == "B2=A"
        )
    }

    @Test func replacesLastMatchingCorrectionValue() {
        #expect(
            BoardCorrectionParser.replaceLastCorrectionValue(
                in: "A1=Ł, H8=, A1=",
                coordinate: "A1",
                value: "Ń"
            ) == "A1=Ł, H8=, A1=Ń"
        )
        #expect(
            BoardCorrectionParser.replaceLastCorrectionValue(
                in: "A1=Ł",
                coordinate: "H8",
                value: "."
            ) == "A1=Ł, H8=."
        )
        #expect(
            BoardCorrectionParser.replaceLastCorrectionValue(
                in: "",
                coordinate: "h8",
                value: "Ż?"
            ) == "H8=Ż?"
        )
    }

    @Test func extractsCorrectionCellKeys() throws {
        let keys = try BoardCorrectionParser.correctionCellKeys(from: "A1=Ł, H8=, J10=.")

        #expect(keys == [
            BoardCorrectionParser.cellKey(row: 0, column: 0),
            BoardCorrectionParser.cellKey(row: 7, column: 7),
            BoardCorrectionParser.cellKey(row: 9, column: 9)
        ])
    }

    @Test func rejectsInvalidCoordinate() throws {
        #expect(throws: ScrabblerError.self) {
            _ = try BoardCorrectionParser.applyCorrections(to: emptyBoard(), input: "Q1=A")
        }
    }

    @Test func rejectsInvalidLetter() throws {
        #expect(throws: ScrabblerError.self) {
            _ = try BoardCorrectionParser.applyCorrections(to: emptyBoard(), input: "A1=X")
        }
    }

    private func emptyBoard() -> Board {
        Board(bonuses: Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size))
    }
}
