import Foundation
import Testing
@testable import ScrabblerKit

@Suite("OCR fixtures")
struct OCRFixtureTests {
    @Test func bundledRegressionFixturesAreAvailable() throws {
        let expected = [
            "all-letters-sample.png",
            "board-real-7273.jpg",
            "board-real-7295.jpg",
            "board-real-7330.jpg",
            "board-real-7331.jpg",
            "board-real-7367.jpg",
            "board-real-7392.jpg",
            "board-real-7403.jpg"
        ]

        for fixture in expected {
            let url = Bundle.module.url(
                forResource: (fixture as NSString).deletingPathExtension,
                withExtension: (fixture as NSString).pathExtension,
                subdirectory: "Fixtures"
            ) ?? Bundle.module.url(
                forResource: (fixture as NSString).deletingPathExtension,
                withExtension: (fixture as NSString).pathExtension
            )
            #expect(url != nil, "Missing fixture \(fixture)")
            if let url {
                #expect(try Data(contentsOf: url).isEmpty == false)
            }
        }
    }

    @Test func nativeVisionReaderReadsBoardLettersFromFixture() async throws {
        let url = try fixtureURL("board-real-7367.jpg")
        let bonuses = try BundledDataLoader.loadBonusLayout()
        let result = try await NativeBoardImageReader().readBoard(from: url, bonuses: bonuses)
        let occupied = result.board.allCells.filter { !$0.isEmpty }

        #expect(occupied.count >= 20)
        #expect(BoardWordExtractor.extractWords(from: result.board).isEmpty == false)
    }

    @Test func repairsSingleMissedTileGapInRealBoard7367() async throws {
        let result = try await readFixture("board-real-7367.jpg")

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(["ŚRODY", "OŚ"]),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)

        #expect(boardLines(repaired.board).contains("ŚRODY"))
    }

    @Test func doesNotRepairEmptyBonusSquareGapInRealBoard7392() async throws {
        let result = try await readFixture("board-real-7392.jpg")

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(["STANOWIŁAŚ", "BAKIEM", "SEZON"]),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)

        #expect(repaired.board[6, 8].letter == nil)
        #expect(!repaired.appliedRepairs.contains { repair in
            repair.row == 6 && repair.column == 8
        })
    }

    @Test func repairsMissedTileAndEdgeFalsePositiveInRealBoard7403() async throws {
        let result = try await readFixture("board-real-7403.jpg")

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(["MĄCIE"]),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)

        #expect(repaired.board[1, 5].letter == nil)
        #expect(repaired.board[1, 8].letter == "C")
        #expect(repaired.board[1, 9].letter == "I")
        #expect(boardLines(repaired.board).contains("MĄCIE"))
    }

    private func readFixture(_ fileName: String) async throws -> BoardReadResult {
        let url = try fixtureURL(fileName)
        let bonuses = try BundledDataLoader.loadBonusLayout()
        return try await NativeBoardImageReader().readBoard(from: url, bonuses: bonuses)
    }

    private func boardLines(_ board: Board) -> [String] {
        BoardWordExtractor.extractWords(from: board).map(\.text)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") ??
            Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }

        throw ScrabblerError.dictionaryNotFound(fileName)
    }
}
