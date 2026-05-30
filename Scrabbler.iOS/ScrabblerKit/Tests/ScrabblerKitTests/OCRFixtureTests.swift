import Foundation
import Testing
@testable import ScrabblerKit

@Suite("OCR fixtures", .serialized)
struct OCRFixtureTests {
    private struct FixtureExpectation {
        let fileName: String
        let minimumOccupiedCells: Int
        let expectedWords: [String]
        let parityGapWords: [String]

        init(
            fileName: String,
            minimumOccupiedCells: Int,
            expectedWords: [String],
            parityGapWords: [String] = []
        ) {
            self.fileName = fileName
            self.minimumOccupiedCells = minimumOccupiedCells
            self.expectedWords = expectedWords
            self.parityGapWords = parityGapWords
        }
    }

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

    @Test(
        "reads representative real board words",
        arguments: [
            FixtureExpectation(fileName: "board-real-7273.jpg", minimumOccupiedCells: 70, expectedWords: ["PAT", "URODNY", "RADA"], parityGapWords: ["STYPA"]),
            FixtureExpectation(fileName: "board-real-7295.jpg", minimumOccupiedCells: 55, expectedWords: ["GODY", "DONGA", "PANIE"], parityGapWords: ["ANIMĄ", "SROCZYMI"]),
            FixtureExpectation(fileName: "board-real-7330.jpg", minimumOccupiedCells: 50, expectedWords: ["TURA"], parityGapWords: ["DLAŃ", "TEGO", "BLATY", "SERIA"]),
            FixtureExpectation(fileName: "board-real-7331.jpg", minimumOccupiedCells: 60, expectedWords: ["ACHOLIA"], parityGapWords: ["REJ", "SZKOLONY"]),
            FixtureExpectation(fileName: "board-real-7367.jpg", minimumOccupiedCells: 30, expectedWords: ["CERO", "DOZA"], parityGapWords: ["STAZIE", "DMIJ"])
        ]
    )
    private func readsRepresentativeRealBoardWords(expectation: FixtureExpectation) async throws {
        let result = try await readFixture(expectation.fileName)
        let occupied = result.cells
        let words = Set(boardLines(result.board))

        #expect(occupied.count >= expectation.minimumOccupiedCells)
        for expectedWord in expectation.expectedWords {
            #expect(words.contains(expectedWord), "\(expectation.fileName) missing \(expectedWord); recognized words: \(words.sorted())")
        }
    }

    @Test(
        "documents remaining OCR parity gaps",
        arguments: [
            FixtureExpectation(fileName: "board-real-7273.jpg", minimumOccupiedCells: 70, expectedWords: [], parityGapWords: ["STYPA"]),
            FixtureExpectation(fileName: "board-real-7295.jpg", minimumOccupiedCells: 55, expectedWords: [], parityGapWords: ["ANIMĄ", "SROCZYMI"]),
            FixtureExpectation(fileName: "board-real-7330.jpg", minimumOccupiedCells: 50, expectedWords: [], parityGapWords: ["DLAŃ", "TEGO", "BLATY", "SERIA"]),
            FixtureExpectation(fileName: "board-real-7331.jpg", minimumOccupiedCells: 60, expectedWords: [], parityGapWords: ["REJ", "SZKOLONY"]),
            FixtureExpectation(fileName: "board-real-7367.jpg", minimumOccupiedCells: 30, expectedWords: [], parityGapWords: ["STAZIE", "DMIJ"])
        ]
    )
    private func documentsRemainingOCRParityGaps(expectation: FixtureExpectation) async throws {
        let result = try await readFixture(expectation.fileName)
        let words = Set(boardLines(result.board))

        for gapWord in expectation.parityGapWords {
            #expect(!words.contains(gapWord), "\(expectation.fileName) now recognizes \(gapWord); move it to the passing fixture expectations.")
        }
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

    @Test(
        "repairs dictionary-backed parity gaps",
        arguments: [
            ("board-real-7295.jpg", "ANIMĄ"),
            ("board-real-7295.jpg", "SROCZYMI"),
            ("board-real-7330.jpg", "DLAŃ"),
            ("board-real-7330.jpg", "BLATY"),
            ("board-real-7330.jpg", "TEGO"),
            ("board-real-7331.jpg", "REJ")
        ]
    )
    private func repairsDictionaryBackedDiacriticParityGaps(fileName: String, expectedWord: String) async throws {
        let result = try await readFixture(fileName)

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(dictionaryWords(for: expectedWord)),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)

        #expect(boardLines(repaired.board).contains(expectedWord))
    }

    private func dictionaryWords(for expectedWord: String) -> [String] {
        switch expectedWord {
        case "SROCZYMI":
            [expectedWord, "OM"]
        case "BLATY":
            [expectedWord, "KA"]
        case "TEGO":
            [expectedWord, "BLATY", "KA", "DEKA", "LG"]
        default:
            [expectedWord]
        }
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
