import Testing
@testable import ScrabblerKit

@Suite("Move solver")
struct MoveSolverTests {
    @Test func firstMoveMustCoverCenterAndUsesCenterWordBonus() throws {
        let solver = solverForWords("ALA")
        let board = emptyBoardWithCenterDoubleWord()

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("ALA"), limit: 10)

        #expect(Set(moves.map(\.score)) == [8])
        #expect(moves[0].word == "ALA")
        #expect(moves.contains { $0.placedTiles.contains { $0.row == 7 && $0.column == 7 } })
    }

    @Test func bundledBonusLayoutScoresFirstMoveCenterDoubleWord() throws {
        let solver = MoveSolver(
            dictionary: PolishWordDictionary.fromWords(["WYLEJĘ"]),
            letterValues: try BundledDataLoader.loadLetterValues()
        )
        let board = Board(bonuses: try BundledDataLoader.loadBonusLayout())

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("WYLEJĘ"), limit: 10)

        #expect(board[7, 7].bonus == .doubleWord)
        #expect(!moves.isEmpty)
        #expect(moves.contains { move in
            move.score == 28 && move.placedTiles.contains { $0.row == 7 && $0.column == 7 }
        })
    }

    @Test func laterMoveMustConnectToExistingTiles() throws {
        let solver = solverForWords("KOT")
        let board = emptyBoardWithCenterDoubleWord().setCell(row: 7, column: 7, letter: "A")

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("KOT"), limit: 10)

        #expect(moves.isEmpty)
    }

    @Test func existingLettersCanBeExtended() throws {
        let solver = solverForWords("KOTY")
        let board = emptyBoardWithCenterDoubleWord()
            .setCell(row: 7, column: 7, letter: "O")
            .setCell(row: 7, column: 8, letter: "T")

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("KY"), limit: 10)

        #expect(moves.count == 1)
        #expect(moves[0].word == "KOTY")
        #expect(moves[0].score == 7)
        #expect(moves[0].placedTiles.count == 2)
    }

    @Test func invalidCrossWordRejectsMove() throws {
        let solver = solverForWords("KOT")
        let board = emptyBoardWithCenterDoubleWord()
            .setCell(row: 7, column: 7, letter: "O")
            .setCell(row: 6, column: 6, letter: "Z")

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("KT"), limit: 10)

        #expect(moves.isEmpty)
    }

    @Test func validCrossWordAddsCrossScore() throws {
        let solver = solverForWords("KOT", "ZK")
        let board = emptyBoardWithCenterDoubleWord()
            .setCell(row: 7, column: 7, letter: "O")
            .setCell(row: 6, column: 6, letter: "Z")

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("KT"), limit: 10)
        let best = try #require(moves.first { $0.crossWords.contains("ZK") })

        #expect(best.word == "KOT")
        #expect(best.score == 8)
    }

    @Test func blankTileScoresZero() throws {
        let solver = solverForWords("ŻAR")
        let moves = try solver.findBestMoves(board: emptyBoardWithCenterDoubleWord(), rack: try Rack.parse("?AR"), limit: 10)

        #expect(moves[0].score == 4)
        #expect(moves[0].placedTiles.contains { $0.letter == "Ż" && $0.isBlank })
    }

    @Test func placingAllSevenRackTilesAddsBonus() throws {
        let solver = solverForWords("KOTARAS")
        let moves = try solver.findBestMoves(board: emptyBoardWithCenterDoubleWord(), rack: try Rack.parse("KOTARAS"), limit: 10)

        #expect(moves.allSatisfy { $0.score == 43 })
        #expect(moves.allSatisfy { $0.placedTiles.count == 7 })
    }

    @Test func placingFewerThanSevenRackTilesDoesNotAddBonus() throws {
        let solver = solverForWords("KOTARA")
        let moves = try solver.findBestMoves(board: emptyBoardWithCenterDoubleWord(), rack: try Rack.parse("KOTARA"), limit: 10)

        #expect(moves.allSatisfy { $0.score == 16 })
        #expect(moves.allSatisfy { $0.placedTiles.count == 6 })
    }

    @Test func blankTileCountsTowardSevenTileBonus() throws {
        let solver = solverForWords("KOTARAS")
        let moves = try solver.findBestMoves(board: emptyBoardWithCenterDoubleWord(), rack: try Rack.parse("?OTARAS"), limit: 10)

        #expect(moves.allSatisfy { $0.score == 39 })
        #expect(moves.allSatisfy { $0.placedTiles.count == 7 })
        #expect(moves.allSatisfy { $0.placedTiles.contains { $0.letter == "K" && $0.isBlank } })
    }

    @Test func returnsOnlyRequestedNumberOfBestMovesInStableOrder() throws {
        let solver = solverForWords("KOT", "TOK", "OK", "TO")
        let moves = try solver.findBestMoves(board: emptyBoardWithCenterDoubleWord(), rack: try Rack.parse("KOT"), limit: 2)

        #expect(moves.count == 2)
        #expect(moves[0].score >= moves[1].score)
        #expect(moves[0].word <= moves[1].word || moves[0].score > moves[1].score)
    }

    @Test func rankedMovesStayStableForRepresentativeConnectedBoard() throws {
        let solver = solverForWords("TOK", "KOT", "OKA", "KOSA", "OSA", "SOK", "TO", "TOS", "SA", "AS")
        let board = emptyBoardWithCenterDoubleWord()
            .setCell(row: 7, column: 7, letter: "O")
            .setCell(row: 7, column: 8, letter: "K")
            .setCell(row: 6, column: 6, letter: "T")
            .setCell(row: 8, column: 6, letter: "S")

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("TAAS"), limit: 5)

        #expect(moves.map(describeMove) == [
            "AS@J8:V:2:AJ8,SJ9|6|OKA",
            "SA@J7:V:2:SJ7,AJ8|6|OKA",
            "OKA@H8:H:1:AJ8|4",
            "AS@F9:V:2:AF9,SF10|4|AS",
            "AS@G10:H:2:AG10,SH10|4|SA"
        ])
    }

    private func solverForWords(_ words: String...) -> MoveSolver {
        MoveSolver(dictionary: PolishWordDictionary.fromWords(words), letterValues: values())
    }

    private func emptyBoardWithCenterDoubleWord() -> Board {
        var bonuses = Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size)
        bonuses[7][7] = .doubleWord
        return Board(bonuses: bonuses)
    }

    private func values() -> [Character: Int] {
        [
            "A": 1,
            "K": 2,
            "L": 2,
            "O": 1,
            "R": 1,
            "S": 1,
            "T": 2,
            "Y": 2,
            "Z": 1,
            "Ż": 5
        ]
    }

    private func describeMove(_ move: Move) -> String {
        let direction = move.direction == .horizontal ? "H" : "V"
        let placed = move.placedTiles
            .map { "\($0.letter)\(coordinate($0.row, $0.column))" }
            .joined(separator: ",")
        let crossWords = move.crossWords.isEmpty ? "" : "|\(move.crossWords.joined(separator: ","))"
        return "\(move.word)@\(coordinate(move.row, move.column)):\(direction):\(move.placedTiles.count):\(placed)|\(move.score)\(crossWords)"
    }

    private func coordinate(_ row: Int, _ column: Int) -> String {
        "\(String(UnicodeScalar(UInt8(ascii: "A") + UInt8(column))))\(row + 1)"
    }
}
