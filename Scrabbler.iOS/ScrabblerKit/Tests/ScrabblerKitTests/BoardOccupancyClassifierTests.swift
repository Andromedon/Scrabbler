import Testing
@testable import ScrabblerKit

@Suite("Board occupancy classifier")
struct BoardOccupancyClassifierTests {
    @Test func emptyDoubleWordBonusIsNotATile() {
        let occupied = BoardOccupancyClassifier.isOccupied(
            orangeRatio: 0.70,
            darkRatio: 0.0,
            whiteRatio: 0.04,
            bonus: .doubleWord
        )

        #expect(!occupied)
    }

    @Test func doubleWordTileWithLargeWhiteGlyphIsATile() {
        let occupied = BoardOccupancyClassifier.isOccupied(
            orangeRatio: 0.70,
            darkRatio: 0.0,
            whiteRatio: 0.12,
            bonus: .doubleWord
        )

        #expect(occupied)
    }

    @Test func emptyLetterBonusWithSmallWhiteLabelIsNotATile() {
        let occupied = BoardOccupancyClassifier.isOccupied(
            orangeRatio: 0.70,
            darkRatio: 0.0,
            whiteRatio: 0.03,
            bonus: .doubleLetter
        )

        #expect(!occupied)
    }

    @Test func letterBonusTileWithLargeWhiteGlyphIsATile() {
        let occupied = BoardOccupancyClassifier.isOccupied(
            orangeRatio: 0.70,
            darkRatio: 0.0,
            whiteRatio: 0.07,
            bonus: .tripleLetter
        )

        #expect(occupied)
    }

    @Test func tileWithDarkGlyphIsATile() {
        let occupied = BoardOccupancyClassifier.isOccupied(
            orangeRatio: 0.70,
            darkRatio: 0.03,
            whiteRatio: 0.0,
            bonus: .none
        )

        #expect(occupied)
    }

    @Test func nonOrangeCellIsNotATile() {
        let occupied = BoardOccupancyClassifier.isOccupied(
            orangeRatio: 0.10,
            darkRatio: 0.04,
            whiteRatio: 0.15,
            bonus: .none
        )

        #expect(!occupied)
    }

    @Test func latentEmptyBonusLabelIsNotTileEvidence() {
        let occupied = BoardOccupancyClassifier.hasLatentTileEvidence(
            orangeRatio: 0.24,
            darkRatio: 0.006,
            whiteRatio: 0.03,
            bonus: .doubleLetter
        )

        #expect(!occupied)
    }

    @Test func latentBonusTileNeedsStrongDarkEvidence() {
        let occupied = BoardOccupancyClassifier.hasLatentTileEvidence(
            orangeRatio: 0.34,
            darkRatio: 0.014,
            whiteRatio: 0.0,
            bonus: .tripleWord
        )

        #expect(occupied)
    }

    @Test func latentNormalTileAcceptsSmallDarkGlyphEvidence() {
        let occupied = BoardOccupancyClassifier.hasLatentTileEvidence(
            orangeRatio: 0.24,
            darkRatio: 0.007,
            whiteRatio: 0.0,
            bonus: .none
        )

        #expect(occupied)
    }

    @Test func latentNormalTileAcceptsWhiteGlyphWithEnoughOrange() {
        let occupied = BoardOccupancyClassifier.hasLatentTileEvidence(
            orangeRatio: 0.31,
            darkRatio: 0.0,
            whiteRatio: 0.03,
            bonus: .none
        )

        #expect(occupied)
    }
}
