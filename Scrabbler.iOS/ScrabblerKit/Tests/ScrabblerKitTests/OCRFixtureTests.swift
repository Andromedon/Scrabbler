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
