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
        let expectedCells: [String: Character]
        let forbiddenCells: [String]

        init(
            fileName: String,
            minimumOccupiedCells: Int,
            expectedWords: [String],
            parityGapWords: [String] = [],
            expectedCells: [String: Character] = [:],
            forbiddenCells: [String] = []
        ) {
            self.fileName = fileName
            self.minimumOccupiedCells = minimumOccupiedCells
            self.expectedWords = expectedWords
            self.parityGapWords = parityGapWords
            self.expectedCells = expectedCells
            self.forbiddenCells = forbiddenCells
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
            "board-real-7403.jpg",
            "board-sample.jpg",
            "board-sample-cropped.png"
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
            FixtureExpectation(
                fileName: "board-real-7273.jpg",
                minimumOccupiedCells: 70,
                expectedWords: ["PAT", "STYPA", "URODNY", "RADA"],
                expectedCells: ["J2": "C", "K2": "E", "L2": "N", "M2": "Ą", "C8": "U", "D8": "R", "E8": "O", "F8": "D", "G8": "N", "H8": "Y"]
            ),
            FixtureExpectation(
                fileName: "board-real-7295.jpg",
                minimumOccupiedCells: 55,
                expectedWords: ["GODY", "DONGA", "PANIE", "ANIMĄ", "SROCZYMI"],
                expectedCells: ["C8": "S", "D8": "R", "E8": "O", "F8": "C", "G8": "Z", "H8": "Y", "I8": "M", "J8": "I"]
            ),
            FixtureExpectation(
                fileName: "board-real-7330.jpg",
                minimumOccupiedCells: 50,
                expectedWords: ["TURA", "DLAŃ", "TEGO", "BLATY", "SERIA", "WIĘŹ"],
                expectedCells: ["B7": "T", "C7": "U", "D7": "R", "E7": "A", "H8": "B", "I8": "L", "J8": "A", "K8": "T", "L8": "Y", "J11": "W", "K11": "I", "L11": "Ę", "M11": "Ź"]
            ),
            FixtureExpectation(
                fileName: "board-real-7331.jpg",
                minimumOccupiedCells: 60,
                expectedWords: ["ACHOLIA", "REJ", "SZKOLONY"],
                expectedCells: ["E7": "S", "F7": "Z", "G7": "K", "H7": "O", "I7": "L", "J7": "O", "K7": "N", "L7": "Y", "G12": "A", "H12": "C", "I12": "H", "J12": "O", "K12": "L", "L12": "I", "M12": "A"]
            ),
            FixtureExpectation(
                fileName: "board-real-7367.jpg",
                minimumOccupiedCells: 30,
                expectedWords: ["CERO", "ŚRODY", "DOZA", "STAZIE", "DMIJ"],
                expectedCells: ["I2": "Ś", "J2": "R", "K2": "O", "L2": "D", "M2": "Y"]
            ),
            FixtureExpectation(
                fileName: "board-real-7392.jpg",
                minimumOccupiedCells: 18,
                expectedWords: ["STANOWIŁAŚ"],
                forbiddenCells: ["I7"]
            ),
            FixtureExpectation(
                fileName: "board-real-7403.jpg",
                minimumOccupiedCells: 40,
                expectedWords: ["TRASY", "TETY", "DAGĘ", "POBROŃ", "WYRU"],
                expectedCells: ["G2": "M", "H2": "Ą", "I2": "C", "J2": "I", "K2": "E"],
                forbiddenCells: ["F2"]
            ),
            FixtureExpectation(
                fileName: "board-sample.jpg",
                minimumOccupiedCells: 35,
                expectedWords: ["GROZIMY", "SŁAWNY", "GLEBY", "ZAMEK", "FAJNY"],
                expectedCells: ["F6": "G", "G6": "R", "H6": "O", "I6": "Z", "J6": "I", "K6": "M", "L6": "Y", "G12": "S", "H12": "Ł", "I12": "A", "J12": "W", "K12": "N", "L12": "Y"]
            ),
            FixtureExpectation(
                fileName: "board-sample-cropped.png",
                minimumOccupiedCells: 35,
                expectedWords: ["SWA", "GROZIMY", "ZAMEK", "FAJNY", "MOPS"],
                parityGapWords: [],
                expectedCells: ["I3": "S", "J3": "W", "K3": "A", "F6": "G", "G6": "R", "H6": "O", "I6": "Z", "J6": "I", "K6": "M", "L6": "Y"],
                forbiddenCells: ["F2", "H4"]
            )
        ]
    )
    private func readsRepresentativeRealBoardWords(expectation: FixtureExpectation) async throws {
        let result = try await readFixture(expectation.fileName)
        dumpOCRIfRequested(fileName: expectation.fileName, result: result, expectation: expectation)
        let occupied = result.cells
        let words = Set(boardLines(result.board))

        #expect(occupied.count >= expectation.minimumOccupiedCells)
        for expectedWord in expectation.expectedWords {
            #expect(words.contains(expectedWord), "\(expectation.fileName) missing \(expectedWord); recognized words: \(words.sorted())")
        }
        for (coordinate, expectedLetter) in expectation.expectedCells {
            let parsed = try parseCoordinate(coordinate)
            #expect(result.board[parsed.row, parsed.column].letter == expectedLetter, "\(expectation.fileName) expected \(coordinate)=\(expectedLetter), got \(result.board[parsed.row, parsed.column].letter.map(String.init) ?? ".")")
        }
        for coordinate in expectation.forbiddenCells {
            let parsed = try parseCoordinate(coordinate)
            #expect(result.board[parsed.row, parsed.column].letter == nil, "\(expectation.fileName) expected \(coordinate) to stay empty, got \(result.board[parsed.row, parsed.column].letter.map(String.init) ?? ".")")
        }
    }

    @Test(
        "documents remaining OCR parity gaps",
        arguments: [
            FixtureExpectation(fileName: "board-real-7273.jpg", minimumOccupiedCells: 70, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-real-7295.jpg", minimumOccupiedCells: 55, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-real-7330.jpg", minimumOccupiedCells: 50, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-real-7331.jpg", minimumOccupiedCells: 60, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-real-7367.jpg", minimumOccupiedCells: 30, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-real-7392.jpg", minimumOccupiedCells: 18, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-real-7403.jpg", minimumOccupiedCells: 40, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-sample.jpg", minimumOccupiedCells: 35, expectedWords: [], parityGapWords: []),
            FixtureExpectation(fileName: "board-sample-cropped.png", minimumOccupiedCells: 35, expectedWords: [], parityGapWords: [])
        ]
    )
    private func documentsRemainingOCRParityGaps(expectation: FixtureExpectation) async throws {
        let result = try await readFixture(expectation.fileName)
        dumpOCRIfRequested(fileName: expectation.fileName, result: result, expectation: expectation)
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
        #expect(boardLines(repaired.board).contains("BAKIEM"))
        #expect(boardLines(repaired.board).contains("SEZON"))
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

    @Test func repairsLowConfidenceWhiteTileWordsInCroppedSampleBoard() async throws {
        let result = try await readFixture("board-sample-cropped.png")

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords([
                "SWA",
                "GROZIMY",
                "ZAMEK",
                "FAJNY",
                "MOPS",
                "SŁAWNY",
                "GLEBY"
            ]),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)

        let words = Set(boardLines(repaired.board))
        #expect(words.contains("SŁAWNY"))
        #expect(words.contains("GLEBY"))
    }

    @Test(
        "repaired board keeps representative fixture words",
        arguments: [
            (
                "board-real-7331.jpg",
                ["REJ", "JADY", "ACHOLIA", "SZKOLONY"],
                [String: Character](),
                [String](),
                ["J8:O->D"],
                ["JAOY"]
            ),
            (
                "board-real-7330.jpg",
                ["DLAŃ", "TEGO", "BLATY", "SERIA", "WIĘŹ"],
                [String: Character](),
                [String](),
                [String](),
                [String]()
            ),
            (
                "board-real-7392.jpg",
                ["STANOWIŁAŚ", "BAKIEM", "SEZON"],
                [String: Character](),
                ["I7"],
                ["H6:.->E", "J6:.->A", "H7:.->Z"],
                ["KIEM"]
            ),
            (
                "board-real-7403.jpg",
                ["MĄCIE", "TRASY", "TETY", "DAGĘ", "POBROŃ", "WYRU"],
                ["G2": "M", "H2": "Ą", "I2": "C", "J2": "I", "K2": "E"],
                ["F2"],
                [String](),
                [String]()
            ),
            (
                "board-sample-cropped.png",
                ["SWA", "GROZIMY", "ZAMEK", "FAJNY", "MOPS", "SŁAWNY", "GLEBY"],
                [String: Character](),
                [String](),
                ["G12:Ę->S", "H12:I->Ł", "K12:Ń->N", "H14:L->E", "J14:A->Y"],
                ["GLLBA", "ĘIAWŃY"]
            )
        ]
    )
    private func repairedBoardKeepsRepresentativeFixtureWords(
        fileName: String,
        expectedWords: [String],
        expectedCells: [String: Character],
        forbiddenCells: [String],
        expectedRepairs: [String],
        forbiddenWords: [String]
    ) async throws {
        let result = try await readFixture(fileName)
        let dictionary = PolishWordDictionary.fromWords(Array(Set(expectedWords.flatMap(dictionaryWords(for:)))))
        let repaired = DictionaryBoardRepairer(
            dictionary: dictionary,
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)
        let words = Set(boardLines(repaired.board))

        for expectedWord in expectedWords {
            #expect(words.contains(expectedWord), "\(fileName) missing repaired word \(expectedWord); repaired words: \(words.sorted())")
        }

        for forbiddenWord in forbiddenWords {
            #expect(!words.contains(forbiddenWord), "\(fileName) kept forbidden repaired word \(forbiddenWord); repaired words: \(words.sorted())")
        }

        for (coordinate, expectedLetter) in expectedCells {
            let parsed = try parseCoordinate(coordinate)
            #expect(repaired.board[parsed.row, parsed.column].letter == expectedLetter, "\(fileName) expected repaired \(coordinate)=\(expectedLetter), got \(repaired.board[parsed.row, parsed.column].letter.map(String.init) ?? ".")")
        }

        for coordinate in forbiddenCells {
            let parsed = try parseCoordinate(coordinate)
            #expect(repaired.board[parsed.row, parsed.column].letter == nil, "\(fileName) expected repaired \(coordinate) to stay empty, got \(repaired.board[parsed.row, parsed.column].letter.map(String.init) ?? ".")")
        }

        let actualRepairs = Set(repaired.appliedRepairs.map(repairSummary))
        let expectedRepairSet = Set(expectedRepairs)
        #expect(
            actualRepairs == expectedRepairSet,
            "\(fileName) expected repairs \(expectedRepairSet.sorted()), actual repairs: \(actualRepairs.sorted())"
        )
    }

    @Test func redScoreBadgeDoesNotLeakIntoNearbyGlyphsInRealBoard7403() async throws {
        let result = try await readFixture("board-real-7403.jpg")

        #expect(result.board[1, 5].letter == nil)
        #expect(result.board[1, 6].letter == "M")
        #expect(result.board[1, 7].letter == "Ą")
        #expect(result.board[1, 8].letter == "C")
        #expect(result.board[1, 9].letter == "I")
        #expect(result.board[1, 10].letter == "E")
        #expect(boardLines(result.board).contains("MĄCIE"))
    }

    @Test func scoreDigitDoesNotOverrideClearGlyphInRealBoard7367() async throws {
        let result = try await readFixture("board-real-7367.jpg")
        let cell = result.cells.first { $0.row == 9 && $0.column == 3 }

        #expect(cell?.candidates.first?.letter == "I")
        #expect(cell?.detectedScoreDigit == 3)
        #expect(result.board[9, 3].letter == "I")
    }

    @Test func wrongScoreDigitDoesNotOverrideClearNHGlyphInRealBoard7331() async throws {
        let result = try await readFixture("board-real-7331.jpg")
        let cell = result.cells.first { $0.row == 6 && $0.column == 10 }

        #expect(cell?.candidates.first?.letter == "N")
        #expect(cell?.detectedScoreDigit == 3)
        #expect(result.board[6, 10].letter == "N")
        #expect(boardLines(result.board).contains("SZKOLONY"))
    }

    @Test func dictionaryRepairDoesNotMutateAlreadyValidCrossWordInRealBoard7330() async throws {
        let result = try await readFixture("board-real-7330.jpg")

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(["DLAŃ", "TEGO", "BLATY", "SERIA", "WIĘŹ", "KA", "LG"]),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)

        #expect(boardLines(repaired.board).contains("WIĘŹ"))
        #expect(!boardLines(repaired.board).contains("WAĘŹ"))
        #expect(!repaired.appliedRepairs.contains { repair in
            repair.row == 10 && repair.column == 10 && repair.originalLetter == "I" && repair.repairedLetter == "A"
        })
    }

    @Test(
        "repairs dictionary-backed fixture gaps together",
        arguments: [
            ("board-real-7273.jpg", ["STYPA"]),
            ("board-real-7295.jpg", ["ANIMĄ", "SROCZYMI"]),
            ("board-real-7330.jpg", ["DLAŃ", "TEGO", "BLATY", "SERIA"]),
            ("board-real-7331.jpg", ["REJ", "JADY"]),
            ("board-real-7367.jpg", ["STAZIE", "DMIJ"]),
            ("board-real-7392.jpg", ["BAKIEM", "SEZON"]),
            ("board-real-7403.jpg", ["MĄCIE"])
        ]
    )
    private func repairsDictionaryBackedFixtureGapsTogether(fileName: String, expectedWords: [String]) async throws {
        let result = try await readFixture(fileName)
        let dictionaryWords = Set(expectedWords.flatMap(dictionaryWords(for:)))

        let repaired = DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(Array(dictionaryWords)),
            letterValues: try BundledDataLoader.loadLetterValues()
        ).repair(result)
        let repairedWords = Set(boardLines(repaired.board))

        for expectedWord in expectedWords {
            #expect(repairedWords.contains(expectedWord), "\(fileName) missing repaired word \(expectedWord); repaired words: \(repairedWords.sorted())")
        }
    }

    @Test(
        "repairs dictionary-backed parity gaps",
        arguments: [
            ("board-real-7273.jpg", "STYPA"),
            ("board-real-7295.jpg", "ANIMĄ"),
            ("board-real-7295.jpg", "SROCZYMI"),
            ("board-real-7330.jpg", "DLAŃ"),
            ("board-real-7330.jpg", "BLATY"),
            ("board-real-7330.jpg", "TEGO"),
            ("board-real-7330.jpg", "SERIA"),
            ("board-real-7331.jpg", "REJ"),
            ("board-real-7331.jpg", "JADY"),
            ("board-real-7367.jpg", "STAZIE"),
            ("board-real-7392.jpg", "BAKIEM"),
            ("board-real-7392.jpg", "SEZON"),
            ("board-real-7403.jpg", "MĄCIE")
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

    private func dumpOCRIfRequested(fileName: String, result: BoardReadResult, expectation: FixtureExpectation? = nil) {
        guard ProcessInfo.processInfo.environment["SCRABBLER_OCR_DEBUG"] == "1" else {
            return
        }

        print("OCR DEBUG \(fileName)")
        printBoardDebug(title: "RAW", result: result, expectation: expectation)

        if let repaired = debugRepairedResult(fileName: fileName, result: result, expectation: expectation) {
            printBoardDebug(title: "REPAIRED", result: repaired, expectation: expectation)
        }

        for cell in result.cells.sorted(by: { lhs, rhs in
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.column < rhs.column
        }) {
            let coordinate = coordinateName(row: cell.row, column: cell.column)
            let letter = cell.letter.map(String.init) ?? "."
            let digit = cell.detectedScoreDigit.map(String.init) ?? "."
            let candidates = cell.candidates.prefix(5)
                .map { "\($0.letter):\(String(format: "%.2f", 1 - $0.distance))\($0.matchedScoreDigit == nil ? "" : "*")" }
                .joined(separator: " ")
            print("\(coordinate)=\(letter) conf=\(String(format: "%.2f", cell.confidence)) digit=\(digit) \(candidates)")
        }
    }

    private func printBoardDebug(title: String, result: BoardReadResult, expectation: FixtureExpectation?) {
        print("\(title) SUMMARY occupied=\(result.board.allCells.filter { !$0.isEmpty }.count) reads=\(result.cells.count) repairs=\(result.appliedRepairs.count)")
        printRenderedBoard(result.board)

        let words = Set(boardLines(result.board))
        print("\(title) WORDS \(words.sorted().joined(separator: ", "))")
        if let expectation {
            let missingWords = expectation.expectedWords.filter { !words.contains($0) }
            if !missingWords.isEmpty {
                print("\(title) MISSING WORDS \(missingWords.joined(separator: ", "))")
            }

            for (coordinate, expectedLetter) in expectation.expectedCells.sorted(by: { $0.key < $1.key }) {
                guard let parsed = try? parseCoordinate(coordinate) else { continue }
                let actual = result.board[parsed.row, parsed.column].letter
                if actual != expectedLetter {
                    print("\(title) MISSING CELL \(coordinate) expected=\(expectedLetter) actual=\(actual.map(String.init) ?? ".")")
                }
            }

            for coordinate in expectation.forbiddenCells.sorted() {
                guard let parsed = try? parseCoordinate(coordinate),
                      let actual = result.board[parsed.row, parsed.column].letter else {
                    continue
                }
                print("\(title) FORBIDDEN CELL \(coordinate)=\(actual)")
            }
        }
        if !result.appliedRepairs.isEmpty {
            let repairs = result.appliedRepairs.map { repair in
                let coordinate = coordinateName(row: repair.row, column: repair.column)
                return "\(coordinate):\(repair.originalLetter.map(String.init) ?? ".")->\(repair.repairedLetter.map(String.init) ?? ".")"
            }
            print("\(title) REPAIRS \(repairs.joined(separator: ", "))")
        }
    }

    private func printRenderedBoard(_ board: Board) {
        for row in 0..<Board.size {
            let line = String((0..<Board.size).map { column in
                board[row, column].letter ?? "."
            })
            print(String(format: "%02d %@", row + 1, line))
        }
    }

    private func debugRepairedResult(
        fileName: String,
        result: BoardReadResult,
        expectation: FixtureExpectation?
    ) -> BoardReadResult? {
        let words = debugRepairWords(fileName: fileName, expectation: expectation)
        guard !words.isEmpty,
              let values = try? BundledDataLoader.loadLetterValues() else {
            return nil
        }

        return DictionaryBoardRepairer(
            dictionary: PolishWordDictionary.fromWords(Array(Set(words.flatMap(dictionaryWords(for:))))),
            letterValues: values
        ).repair(result)
    }

    private func debugRepairWords(fileName: String, expectation: FixtureExpectation?) -> [String] {
        var words = expectation?.expectedWords ?? []
        switch fileName {
        case "board-real-7273.jpg":
            words.append(contentsOf: ["STYPA"])
        case "board-real-7295.jpg":
            words.append(contentsOf: ["ANIMĄ", "SROCZYMI"])
        case "board-real-7330.jpg":
            words.append(contentsOf: ["DLAŃ", "TEGO", "BLATY", "SERIA", "WIĘŹ"])
        case "board-real-7331.jpg":
            words.append(contentsOf: ["REJ", "JADY"])
        case "board-real-7367.jpg":
            words.append(contentsOf: ["ŚRODY", "STAZIE", "DMIJ"])
        case "board-real-7392.jpg":
            words.append(contentsOf: ["STANOWIŁAŚ", "BAKIEM", "SEZON"])
        case "board-real-7403.jpg":
            words.append(contentsOf: ["MĄCIE"])
        case "board-sample-cropped.png":
            words.append(contentsOf: ["SWA", "GROZIMY", "ZAMEK", "FAJNY", "MOPS", "SŁAWNY", "GLEBY"])
        default:
            break
        }
        return Array(Set(words))
    }

    private func parseCoordinate(_ coordinate: String) throws -> (row: Int, column: Int) {
        guard let first = coordinate.uppercased().unicodeScalars.first,
              first.value >= UnicodeScalar("A").value,
              first.value <= UnicodeScalar("O").value,
              let rowNumber = Int(coordinate.dropFirst()),
              (1...Board.size).contains(rowNumber) else {
            throw ScrabblerError.invalidCorrection(coordinate)
        }

        return (rowNumber - 1, Int(first.value - UnicodeScalar("A").value))
    }

    private func coordinateName(row: Int, column: Int) -> String {
        "\(String(UnicodeScalar(UInt8(ascii: "A") + UInt8(column))))\(row + 1)"
    }

    private func repairSummary(_ repair: BoardRepair) -> String {
        let coordinate = coordinateName(row: repair.row, column: repair.column)
        let original = repair.originalLetter.map(String.init) ?? "."
        let repaired = repair.repairedLetter.map(String.init) ?? "."
        return "\(coordinate):\(original)->\(repaired)"
    }
}
