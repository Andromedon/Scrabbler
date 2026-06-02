import Testing
@testable import ScrabblerKit

@Suite("Move formatter")
struct MoveFormatterTests {
    @Test func coordinateFormatsBoardCells() {
        #expect(BoardCoordinateFormatter.coordinate(row: 0, column: 0) == "A1")
        #expect(BoardCoordinateFormatter.coordinate(row: 7, column: 7) == "H8")
        #expect(BoardCoordinateFormatter.coordinate(row: 14, column: 14) == "O15")
    }

    @Test func placedTilesTextUsesUiBlankMarkerSuffix() {
        let move = Move(
            word: "ŻAR",
            row: 7,
            column: 6,
            direction: .horizontal,
            placedTiles: [
                PlacedTile(row: 7, column: 6, letter: "Ż", isBlank: true),
                PlacedTile(row: 7, column: 7, letter: "A", isBlank: false)
            ],
            score: 4,
            crossWords: []
        )

        #expect(MoveFormatter.placedTilesText(move) == "ŻG8?, AH8")
    }

    @Test func formatsMoveSummaryLabels() {
        let horizontal = Move(
            word: "ŻAR",
            row: 7,
            column: 6,
            direction: .horizontal,
            placedTiles: [
                PlacedTile(row: 7, column: 6, letter: "Ż", isBlank: true),
                PlacedTile(row: 7, column: 7, letter: "A", isBlank: false)
            ],
            score: 4,
            crossWords: ["ZA", "AR"]
        )
        let vertical = Move(
            word: "OSA",
            row: 5,
            column: 9,
            direction: .vertical,
            placedTiles: [],
            score: 12,
            crossWords: []
        )

        #expect(MoveFormatter.coordinateDirectionText(horizontal) == "G8 →")
        #expect(MoveFormatter.coordinateDirectionText(vertical) == "J6 ↓")
        #expect(MoveFormatter.placedTilesLabelText(horizontal) == "Placed: ŻG8?, AH8")
        #expect(MoveFormatter.crossWordsText(horizontal) == "ZA, AR")
        #expect(MoveFormatter.crossWordsLabelText(horizontal) == "Crosses: ZA, AR")
        #expect(MoveFormatter.crossWordsText(vertical) == "-")
        #expect(MoveFormatter.crossWordsLabelText(vertical) == "Crosses: -")
    }

    @Test func compactDescriptionIncludesBlankMarkersAndCrossWords() {
        let move = Move(
            word: "OSA",
            row: 5,
            column: 9,
            direction: .vertical,
            placedTiles: [
                PlacedTile(row: 5, column: 9, letter: "O", isBlank: true),
                PlacedTile(row: 6, column: 9, letter: "S", isBlank: false),
                PlacedTile(row: 7, column: 9, letter: "A", isBlank: false)
            ],
            score: 12,
            crossWords: ["OKA"]
        )

        #expect(MoveFormatter.compactDescription(move) == "OSA@J6:V:3:O?J6,SJ7,AJ8|12|OKA")
    }

    @Test func stableIDIncludesBlankState() {
        let blankMove = Move(
            word: "ŻAR",
            row: 7,
            column: 6,
            direction: .horizontal,
            placedTiles: [PlacedTile(row: 7, column: 6, letter: "Ż", isBlank: true)],
            score: 4,
            crossWords: []
        )
        let regularMove = Move(
            word: "ŻAR",
            row: 7,
            column: 6,
            direction: .horizontal,
            placedTiles: [PlacedTile(row: 7, column: 6, letter: "Ż", isBlank: false)],
            score: 4,
            crossWords: []
        )

        #expect(MoveFormatter.stableID(blankMove) != MoveFormatter.stableID(regularMove))
    }
}
