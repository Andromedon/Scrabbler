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

    @Test func premiumCrossWordRankingParityVector() throws {
        let solver = solverForWords("TOK", "KOT", "OKA", "KOSA", "OSA", "SOK", "TO", "TOS", "SA", "AS")
        let board = parityBoardWithPremiumCross()

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("TAAS"), limit: 8)

        #expect(moves.map(describeMove) == [
            "AS@J8:V:2:AJ8,SJ9|12|OKA",
            "SA@J7:V:2:SJ7,AJ8|12|OKA",
            "OKA@H8:H:1:AJ8|8",
            "AS@F9:V:2:AF9,SF10|4|AS",
            "AS@G10:H:2:AG10,SH10|4|SA",
            "SA@F8:V:2:SF8,AF9|4|AS",
            "SA@F10:H:2:SF10,AG10|4|SA",
            "AS@F9:H:1:AF9|2"
        ])
    }

    @Test func realBoardShapeRankingParityVector() throws {
        let solver = solverForWords(
            "STAZIE", "STAZIĘ", "DOZA", "CERO", "DMIJ", "ADWA", "ODA", "OŚ",
            "STA", "TA", "ZA", "ZIE", "RA", "AS", "SA", "SI", "AD", "WA", "DA",
            "WADA", "WAD", "DWA", "DROGA", "ROD", "RÓD", "DOM", "MIJ", "MAJ"
        )
        let board = realBoardShape7367()

        let moves = try solver.findBestMoves(board: board, rack: try Rack.parse("STAZIE"), limit: 12)

        #expect(moves.map(describeMove) == [
            "STAZIE@G9:H:6:SG9,TH9,AI9,ZJ9,IK9,EL9|10|TA",
            "STAZIE@G9:V:6:SG9,TG10,AG11,ZG12,IG13,EG14|10|TA",
            "STAZIE@F7:H:5:SF7,TG7,ZI7,IJ7,EK7|9|SA",
            "STAZIE@H9:H:6:SH9,TI9,AJ9,ZK9,IL9,EM9|9|SA",
            "STAZIE@G10:V:6:SG10,TG11,AG12,ZG13,IG14,EG15|9|SA",
            "STAZIE@I10:V:6:SI10,TI11,AI12,ZI13,II14,EI15|9|AS",
            "STAZIE@H11:H:6:SH11,TI11,AJ11,ZK11,IL11,EM11|9|AS",
            "STA@G9:H:3:SG9,TH9,AI9|7|TA",
            "STA@G9:V:3:SG9,TG10,AG11|7|TA",
            "STA@D4:V:3:SD4,TD5,AD6|6|AS",
            "STA@K4:H:3:SK4,TL4,AM4|6|SA",
            "STA@K6:H:3:SK6,TL6,AM6|6|AS"
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

    private func parityBoardWithPremiumCross() -> Board {
        var bonuses = Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size)
        bonuses[7][7] = .doubleWord
        bonuses[7][9] = .doubleWord
        return Board(bonuses: bonuses)
            .setCell(row: 7, column: 7, letter: "O")
            .setCell(row: 7, column: 8, letter: "K")
            .setCell(row: 6, column: 6, letter: "T")
            .setCell(row: 8, column: 6, letter: "S")
    }

    private func realBoardShape7367() -> Board {
        var bonuses = Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size)
        bonuses[7][7] = .doubleWord
        bonuses[0][8] = .tripleLetter
        bonuses[4][7] = .doubleWord
        bonuses[4][9] = .doubleLetter
        bonuses[9][1] = .tripleWord

        return Board(bonuses: bonuses)
            .setCell(row: 0, column: 5, letter: "C")
            .setCell(row: 0, column: 6, letter: "E")
            .setCell(row: 0, column: 7, letter: "R")
            .setCell(row: 0, column: 8, letter: "O")
            .setCell(row: 1, column: 8, letter: "Ś")
            .setCell(row: 1, column: 9, letter: "R")
            .setCell(row: 1, column: 10, letter: "O")
            .setCell(row: 1, column: 11, letter: "D")
            .setCell(row: 1, column: 12, letter: "Y")
            .setCell(row: 3, column: 7, letter: "A")
            .setCell(row: 4, column: 5, letter: "W")
            .setCell(row: 4, column: 7, letter: "D")
            .setCell(row: 4, column: 8, letter: "O")
            .setCell(row: 4, column: 9, letter: "Z")
            .setCell(row: 4, column: 10, letter: "A")
            .setCell(row: 5, column: 4, letter: "S")
            .setCell(row: 5, column: 7, letter: "W")
            .setCell(row: 6, column: 7, letter: "A")
            .setCell(row: 7, column: 5, letter: "A")
            .setCell(row: 9, column: 1, letter: "D")
            .setCell(row: 9, column: 2, letter: "M")
            .setCell(row: 9, column: 3, letter: "I")
            .setCell(row: 9, column: 4, letter: "J")
            .setCell(row: 9, column: 7, letter: "A")
    }

    private func values() -> [Character: Int] {
        [
            "A": 1,
            "C": 2,
            "D": 2,
            "E": 1,
            "I": 1,
            "J": 3,
            "K": 2,
            "L": 2,
            "M": 2,
            "O": 1,
            "R": 1,
            "S": 1,
            "T": 2,
            "W": 1,
            "Y": 2,
            "Z": 1,
            "Ę": 5,
            "Ś": 5,
            "Ó": 5,
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
