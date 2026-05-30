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
}
