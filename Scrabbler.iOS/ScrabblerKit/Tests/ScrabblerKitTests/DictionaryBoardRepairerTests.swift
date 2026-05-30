import Testing
@testable import ScrabblerKit

@Suite("Dictionary board repairer")
struct DictionaryBoardRepairerTests {
    @Test func fixesNHWhenDictionaryAndScoreDigitAgree() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "N")
            .setCell(row: 7, column: 8, letter: "A")
            .setCell(row: 7, column: 9, letter: "T")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 7, column: 7, letter: "N", confidence: 0.66, scoreDigit: 3, candidates: [
                LetterCandidate(letter: "N", distance: 0.20),
                LetterCandidate(letter: "H", distance: 0.24)
            ])
        ])

        let repaired = repairer(words: "HAT").repair(result)

        #expect(repaired.board[7, 7].letter == "H")
        #expect(repaired.appliedRepairs.contains { $0.row == 7 && $0.column == 7 && $0.originalLetter == "N" && $0.repairedLetter == "H" })
    }

    @Test func fixesDBWhenDictionaryAndScoreDigitAgree() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "B")
            .setCell(row: 7, column: 8, letter: "O")
            .setCell(row: 7, column: 9, letter: "M")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 7, column: 7, letter: "B", confidence: 0.62, scoreDigit: 2, candidates: [
                LetterCandidate(letter: "B", distance: 0.20),
                LetterCandidate(letter: "D", distance: 0.27)
            ])
        ])

        let repaired = repairer(words: "DOM").repair(result)

        #expect(repaired.board[7, 7].letter == "D")
    }

    @Test func refusesAmbiguousRepairs() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "C")
            .setCell(row: 7, column: 8, letter: "A")
            .setCell(row: 7, column: 9, letter: "T")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 7, column: 7, letter: "C", confidence: 0.60, candidates: [
                LetterCandidate(letter: "B", distance: 0.25),
                LetterCandidate(letter: "D", distance: 0.25)
            ])
        ])

        let repaired = repairer(words: "BAT", "DAT").repair(result)

        #expect(repaired.board[7, 7].letter == "C")
        #expect(repaired.appliedRepairs.isEmpty)
    }

    @Test func doesNotOverrideClearHighConfidenceLetter() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "B")
            .setCell(row: 7, column: 8, letter: "O")
            .setCell(row: 7, column: 9, letter: "M")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 7, column: 7, letter: "B", confidence: 0.94, scoreDigit: 2, candidates: [
                LetterCandidate(letter: "D", distance: 0.20)
            ])
        ])

        let repaired = repairer(words: "DOM").repair(result)

        #expect(repaired.board[7, 7].letter == "B")
        #expect(repaired.appliedRepairs.isEmpty)
    }

    @Test func repairsDiacriticVariantWhenDictionaryRequiresIt() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "S")
            .setCell(row: 7, column: 8, letter: "R")
            .setCell(row: 7, column: 9, letter: "O")
            .setCell(row: 7, column: 10, letter: "D")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 7, column: 7, letter: "S", confidence: 0.96, candidates: [
                LetterCandidate(letter: "S", distance: 0.04)
            ])
        ])

        let repaired = repairer(words: "ŚRODY").repair(result)

        #expect(repaired.board[7, 7].letter == "Ś")
        #expect(repaired.appliedRepairs.contains { $0.row == 7 && $0.column == 7 && $0.repairedLetter == "Ś" })
    }

    @Test func repairsDiacriticVariantWhenCrossWordAlsoMatches() {
        let board = emptyBoard()
            .setCell(row: 6, column: 7, letter: "O")
            .setCell(row: 7, column: 7, letter: "S")
            .setCell(row: 7, column: 8, letter: "R")
            .setCell(row: 7, column: 9, letter: "O")
            .setCell(row: 7, column: 10, letter: "D")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 7, column: 7, letter: "S", confidence: 0.50, candidates: [
                LetterCandidate(letter: "S", distance: 0.50)
            ])
        ])

        let repaired = repairer(words: "ŚRODY", "OŚ").repair(result)

        #expect(repaired.board[7, 7].letter == "Ś")
    }


    @Test func fillsSingleMissedTileGapFromDictionaryPattern() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "Ś")
            .setCell(row: 7, column: 9, letter: "O")
            .setCell(row: 7, column: 10, letter: "D")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            CellRead(row: 7, column: 8, letter: nil, confidence: 0)
        ])

        let repaired = repairer(words: "ŚRODY").repair(result)

        #expect(repaired.board[7, 8].letter == "R")
        #expect(BoardWordExtractor.extractWords(from: repaired.board).map(\.text).contains("ŚRODY"))
    }

    @Test func dropsLowConfidenceEdgeFalsePositiveAndFillsGap() {
        let board = emptyBoard()
            .setCell(row: 1, column: 5, letter: "W")
            .setCell(row: 1, column: 6, letter: "M")
            .setCell(row: 1, column: 7, letter: "Ą")
            .setCell(row: 1, column: 8, letter: "C")
            .setCell(row: 1, column: 10, letter: "E")
        let result = BoardReadResult(board: board, cells: [
            cell(row: 1, column: 5, letter: "W", confidence: 0.50, candidates: [
                LetterCandidate(letter: "W", distance: 0.50)
            ]),
            CellRead(row: 1, column: 9, letter: nil, confidence: 0)
        ])

        let repaired = repairer(words: "MĄCIE").repair(result)

        #expect(repaired.board[1, 5].letter == nil)
        #expect(repaired.board[1, 9].letter == "I")
        #expect(BoardWordExtractor.extractWords(from: repaired.board).map(\.text).contains("MĄCIE"))
        #expect(repaired.appliedRepairs.contains { $0.row == 1 && $0.column == 5 && $0.originalLetter == "W" && $0.repairedLetter == nil })
    }

    @Test func fillsTwoVisualGapsWhenDictionaryPatternIsUnique() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "B")
            .setCell(row: 7, column: 9, letter: "A")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            CellRead(row: 7, column: 8, letter: nil, confidence: 0),
            CellRead(row: 7, column: 10, letter: nil, confidence: 0)
        ])

        let repaired = repairer(words: "BLATY").repair(result)

        #expect(repaired.board[7, 8].letter == "L")
        #expect(repaired.board[7, 10].letter == "T")
        #expect(BoardWordExtractor.extractWords(from: repaired.board).map(\.text).contains("BLATY"))
    }

    @Test func fillsTwoVisualGapsAndOneLowConfidenceMismatchWhenUnique() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "B")
            .setCell(row: 7, column: 9, letter: "L")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            CellRead(row: 7, column: 8, letter: nil, confidence: 0),
            cell(row: 7, column: 9, letter: "L", confidence: 0.30, candidates: [
                LetterCandidate(letter: "L", distance: 0.70)
            ]),
            CellRead(row: 7, column: 10, letter: nil, confidence: 0)
        ])

        let repaired = repairer(words: "BLATY").repair(result)

        #expect(repaired.board[7, 8].letter == "L")
        #expect(repaired.board[7, 9].letter == "A")
        #expect(repaired.board[7, 10].letter == "T")
        #expect(BoardWordExtractor.extractWords(from: repaired.board).map(\.text).contains("BLATY"))
    }

    @Test func refusesAmbiguousTwoGapPattern() {
        let board = emptyBoard()
            .setCell(row: 7, column: 7, letter: "B")
            .setCell(row: 7, column: 9, letter: "A")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            CellRead(row: 7, column: 8, letter: nil, confidence: 0),
            CellRead(row: 7, column: 10, letter: nil, confidence: 0)
        ])

        let repaired = repairer(words: "BLATY", "BRANY").repair(result)

        #expect(repaired.board[7, 8].letter == nil)
        #expect(repaired.board[7, 10].letter == nil)
        #expect(repaired.appliedRepairs.isEmpty)
    }

    @Test func refusesTwoGapPatternWhenItBreaksCrossWord() {
        let board = emptyBoard()
            .setCell(row: 6, column: 8, letter: "O")
            .setCell(row: 7, column: 7, letter: "B")
            .setCell(row: 7, column: 9, letter: "A")
            .setCell(row: 7, column: 11, letter: "Y")
        let result = BoardReadResult(board: board, cells: [
            CellRead(row: 7, column: 8, letter: nil, confidence: 0),
            CellRead(row: 7, column: 10, letter: nil, confidence: 0)
        ])

        let repaired = repairer(words: "BLATY").repair(result)

        #expect(repaired.board[7, 8].letter == nil)
        #expect(repaired.board[7, 10].letter == nil)
        #expect(repaired.appliedRepairs.isEmpty)
    }

    @Test func fillsGapAndFixesNeighborWhenCrossWordsMatch() {
        let board = emptyBoard()
            .setCell(row: 4, column: 9, letter: "D")
            .setCell(row: 4, column: 10, letter: "L")
            .setCell(row: 5, column: 8, letter: "T")
            .setCell(row: 5, column: 10, letter: "E")
            .setCell(row: 5, column: 11, letter: "O")
            .setCell(row: 6, column: 9, letter: "K")
            .setCell(row: 7, column: 9, letter: "A")
        let result = BoardReadResult(board: board, cells: [
            CellRead(row: 5, column: 9, letter: nil, confidence: 0),
            cell(row: 5, column: 10, letter: "E", confidence: 0.30, candidates: [
                LetterCandidate(letter: "E", distance: 0.70)
            ])
        ])

        let repaired = repairer(words: "TEGO", "DEKA", "LG").repair(result)

        #expect(repaired.board[5, 9].letter == "E")
        #expect(repaired.board[5, 10].letter == "G")
        #expect(BoardWordExtractor.extractWords(from: repaired.board).map(\.text).contains("TEGO"))
    }

    private func emptyBoard() -> Board {
        Board(bonuses: Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size))
    }

    private func cell(
        row: Int,
        column: Int,
        letter: Character,
        confidence: Double,
        scoreDigit: Int? = nil,
        candidates: [LetterCandidate]
    ) -> CellRead {
        CellRead(
            row: row,
            column: column,
            letter: letter,
            confidence: confidence,
            candidates: candidates,
            detectedScoreDigit: scoreDigit
        )
    }

    private func repairer(words: String...) -> DictionaryBoardRepairer {
        DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(words),
            letterValues: [
                "A": 1,
                "B": 3,
                "C": 2,
                "D": 2,
                "H": 3,
                "N": 1,
                "O": 1,
                "T": 2
            ]
        )
    }
}
