import Testing
@testable import ScrabblerKit

@Suite("Board review text formatter")
struct BoardReviewTextFormatterTests {
    @Test func formatsBonusText() {
        #expect(BoardReviewTextFormatter.bonusText(.doubleLetter) == "2L")
        #expect(BoardReviewTextFormatter.bonusText(.tripleLetter) == "3L")
        #expect(BoardReviewTextFormatter.bonusText(.doubleWord) == "2W")
        #expect(BoardReviewTextFormatter.bonusText(.tripleWord) == "3W")
        #expect(BoardReviewTextFormatter.bonusText(.none) == nil)
    }

    @Test func formatsAutoRepairStatusWithCoordinatesAndDots() {
        let repairs = [
            BoardRepair(row: 1, column: 7, originalLetter: nil, repairedLetter: "R", reason: "dictionary: ŚRODY"),
            BoardRepair(row: 4, column: 8, originalLetter: "D", repairedLetter: "O", reason: "dictionary: DOZA")
        ]

        #expect(BoardReviewTextFormatter.autoRepairStatusText(repairs) == "H2 .→R, I5 D→O")
    }

    @Test func stripsDictionaryPrefixFromRepairReason() {
        #expect(BoardReviewTextFormatter.shortRepairReason("dictionary: MĄCIE") == "MĄCIE")
        #expect(BoardReviewTextFormatter.shortRepairReason("score digit") == "score digit")
    }

    @Test func formatsReviewReasons() {
        #expect(
            BoardReviewTextFormatter.reviewReasonText(
                for: CellReview(
                    row: 0,
                    column: 0,
                    letter: "H",
                    confidence: 0.5,
                    candidates: ["H", "N"],
                    detectedScoreDigit: 1,
                    reason: .scoreDigitMismatch(detected: 1, expected: 3)
                )
            ) == "value 1, H=3"
        )
        #expect(
            BoardReviewTextFormatter.reviewReasonText(
                for: CellReview(row: 0, column: 0, letter: nil, confidence: 0.0, candidates: ["R"], detectedScoreDigit: nil, reason: .possibleMissedTile)
            ) == "possible missed tile"
        )
        #expect(
            BoardReviewTextFormatter.reviewReasonText(
                for: CellReview(row: 0, column: 0, letter: "O", confidence: 0.574, candidates: ["O"], detectedScoreDigit: nil, reason: .lowConfidence)
            ) == "low confidence 57%"
        )
        #expect(
            BoardReviewTextFormatter.reviewReasonText(
                for: CellReview(row: 0, column: 0, letter: "D", confidence: 0.7, candidates: ["D", "O"], detectedScoreDigit: nil, reason: .closeCandidates)
            ) == "close candidates"
        )
    }

    @Test func formatsReviewStatusPreviewAndOverflow() {
        let cells = (0..<11).map { column in
            CellReview(
                row: 0,
                column: column,
                letter: column == 0 ? nil : "A",
                confidence: 0.5,
                candidates: column == 0 ? ["R"] : ["A", "Ą", "O", "D"],
                detectedScoreDigit: nil,
                reason: .closeCandidates
            )
        }

        #expect(
            BoardReviewTextFormatter.reviewStatusText(for: cells) ==
                "Check amber cells: A1=. (R), B1=A (A/Ą/O), C1=A (A/Ą/O), D1=A (A/Ą/O), E1=A (A/Ą/O), F1=A (A/Ą/O), G1=A (A/Ą/O), H1=A (A/Ą/O), I1=A (A/Ą/O), J1=A (A/Ą/O)…"
        )
    }

    @Test func formatsInvalidWordStatus() {
        let words = [
            BoardWord(text: "MĄO", direction: .horizontal, coordinates: [(row: 0, column: 4), (row: 0, column: 5), (row: 0, column: 6)]),
            BoardWord(text: "ŚODA", direction: .horizontal, coordinates: [(row: 1, column: 8), (row: 1, column: 9), (row: 1, column: 10), (row: 1, column: 11)])
        ]

        #expect(BoardReviewTextFormatter.invalidWordsStatusText([]) == "All detected board words are in the dictionary.")
        #expect(BoardReviewTextFormatter.invalidWordsStatusText(words) == "Check words: MĄO E1, ŚODA I2")
    }
}
