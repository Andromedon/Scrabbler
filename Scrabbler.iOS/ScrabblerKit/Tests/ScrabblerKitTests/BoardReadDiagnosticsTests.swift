import Testing
@testable import ScrabblerKit

@Suite("Board read diagnostics")
struct BoardReadDiagnosticsTests {
    private let values: [Character: Int] = ["A": 1, "B": 3, "N": 1, "H": 3, "O": 1]

    @Test func flagsScoreDigitMismatchForUncertainLetter() {
        let reviews = BoardReadDiagnostics.reviewCells(
            in: [
                CellRead(
                    row: 1,
                    column: 2,
                    letter: "N",
                    confidence: 0.72,
                    detectedScoreDigit: 3
                )
            ],
            letterValues: values
        )

        #expect(reviews.map(\.reason) == [.scoreDigitMismatch(detected: 3, expected: 1)])
    }

    @Test func ignoresScoreDigitMismatchForHighConfidenceLetter() {
        let reviews = BoardReadDiagnostics.reviewCells(
            in: [
                CellRead(
                    row: 1,
                    column: 2,
                    letter: "N",
                    confidence: 0.96,
                    detectedScoreDigit: 3
                )
            ],
            letterValues: values
        )

        #expect(reviews.isEmpty)
    }

    @Test func flagsPossibleMissedTileCandidate() {
        let reviews = BoardReadDiagnostics.reviewCells(
            in: [
                CellRead(
                    row: 3,
                    column: 4,
                    letter: nil,
                    candidates: [LetterCandidate(letter: "A", distance: 0.12)],
                    detectedScoreDigit: 1
                )
            ],
            letterValues: values
        )

        #expect(reviews.first?.reason == .possibleMissedTile)
        #expect(reviews.first?.candidates == ["A"])
    }

    @Test func flagsLowConfidenceLetter() {
        let reviews = BoardReadDiagnostics.reviewCells(
            in: [
                CellRead(
                    row: 5,
                    column: 6,
                    letter: "O",
                    confidence: 0.50,
                    candidates: [LetterCandidate(letter: "O", distance: 0.10)],
                    detectedScoreDigit: 1
                )
            ],
            letterValues: values
        )

        #expect(reviews.first?.reason == .lowConfidence)
    }

    @Test func flagsCloseCandidates() {
        let reviews = BoardReadDiagnostics.reviewCells(
            in: [
                CellRead(
                    row: 7,
                    column: 8,
                    letter: "B",
                    confidence: 0.76,
                    candidates: [
                        LetterCandidate(letter: "B", distance: 0.12),
                        LetterCandidate(letter: "O", distance: 0.16)
                    ],
                    detectedScoreDigit: 3
                )
            ],
            letterValues: values
        )

        #expect(reviews.first?.reason == .closeCandidates)
    }

    @Test func ignoresAutoRepairedCells() {
        let reviews = BoardReadDiagnostics.reviewCells(
            in: [
                CellRead(
                    row: 1,
                    column: 2,
                    letter: nil,
                    candidates: [LetterCandidate(letter: "A", distance: 0.12)],
                    detectedScoreDigit: 1
                )
            ],
            letterValues: values,
            ignoringCellKeys: ["1:2"]
        )

        #expect(reviews.isEmpty)
    }
}
