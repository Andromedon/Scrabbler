import Foundation
import PhotosUI
import SwiftUI
import ScrabblerKit

struct InvalidBoardWord: Identifiable, Equatable {
    let text: String
    let coordinate: String
    let coordinates: [(row: Int, column: Int)]

    var id: String {
        "\(coordinate):\(text)"
    }

    static func == (lhs: InvalidBoardWord, rhs: InvalidBoardWord) -> Bool {
        lhs.text == rhs.text &&
            lhs.coordinate == rhs.coordinate &&
            lhs.coordinates.map { [$0.row, $0.column] } == rhs.coordinates.map { [$0.row, $0.column] }
    }
}

struct AutoRepairReviewItem: Identifiable, Equatable {
    let row: Int
    let column: Int
    let coordinate: String
    let originalLetter: Character?
    let repairedLetter: Character?
    let reason: String

    var id: String {
        "\(row):\(column):\(originalLetter.map(String.init) ?? "."):\(repairedLetter.map(String.init) ?? ".")"
    }
}

struct OCRReviewItem: Identifiable, Equatable {
    let row: Int
    let column: Int
    let coordinate: String
    let letter: Character?
    let confidence: Double
    let candidates: [Character]
    let detectedScoreDigit: Int?
    let reason: String

    var id: String {
        "\(row):\(column):\(letter.map(String.init) ?? "."):\(reason)"
    }
}

struct CorrectionTarget: Equatable {
    let row: Int
    let column: Int
    let coordinate: String
}

@MainActor
final class AppState: ObservableObject {
    enum Screen {
        case home
        case boardCorrection
        case rackInput
        case results
    }

    @Published var screen: Screen = .home
    @Published var board: Board
    @Published var correctionsText = ""
    @Published var selectedCorrectionTarget: CorrectionTarget?
    @Published var rackText = ""
    @Published var results: [Move] = []
    @Published var selectedMove: Move?
    @Published var detectedTileCount = 0
    @Published var boardValidationStatus = ""
    @Published var autoRepairStatus = ""
    @Published var autoRepairItems: [AutoRepairReviewItem] = []
    @Published var ocrReviewItems: [OCRReviewItem] = []
    @Published var autoRepairedCellKeys: Set<String> = []
    @Published var reviewCellKeys: Set<String> = []
    @Published var invalidWordCellKeys: Set<String> = []
    @Published var invalidBoardWords: [InvalidBoardWord] = []
    @Published var reviewStatus = ""
    @Published var isBusy = false
    @Published var status = ""
    @Published var lastBoardReadTiming = ""
    @Published var lastDictionaryLoadTiming = ""
    @Published var lastSolveTiming = ""
    @Published var dictionaryStatus = ""
    @Published var isDictionaryReady = false
    @Published var isDictionaryCacheAvailable = false
    @Published var isDictionaryLoading = false
    @Published var errorMessage: String?

    private let bonuses: [[BonusType]]
    private let reader: BoardImageReading
    private let letterValues: [Character: Int]
    private var dictionary: PolishWordDictionary?
    private var solver: MoveSolver?
    private var solverLoadTask: Task<SolverLoadResult, Error>?
    private var lastCellReads: [CellRead] = []
    private var manuallyCorrectedCellKeys: Set<String> = []

    init() {
        let loadedBonuses = (try? BundledDataLoader.loadBonusLayout()) ??
            Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size)
        let loadedValues = (try? BundledDataLoader.loadLetterValues()) ?? [:]

        self.bonuses = loadedBonuses
        self.board = Board(bonuses: loadedBonuses)
        self.reader = NativeBoardImageReader()
        self.letterValues = loadedValues
        self.dictionaryStatus = "Dictionary not loaded"
        refreshDictionaryCacheAvailability()
    }

    func loadDictionary() {
        startDictionaryLoad()
    }

    func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isBusy = true
        status = "Reading board..."
        lastBoardReadTiming = ""
        let totalStartedAt = Date()
        defer {
            isBusy = false
            status = ""
        }

        do {
            let importStartedAt = Date()
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not read the selected image."
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("scrabbler-selected-board")
                .appendingPathExtension("jpg")
            try data.write(to: url, options: .atomic)
            let importSeconds = Date().timeIntervalSince(importStartedAt)

            let ocrStartedAt = Date()
            let result = try await reader.readBoard(from: url, bonuses: bonuses)
            let ocrSeconds = Date().timeIntervalSince(ocrStartedAt)
            board = result.board
            lastCellReads = result.cells
            manuallyCorrectedCellKeys = []
            correctionsText = ""
            selectedCorrectionTarget = nil
            autoRepairStatus = ""
            autoRepairItems = []
            ocrReviewItems = []
            autoRepairedCellKeys = []
            invalidWordCellKeys = []
            invalidBoardWords = []
            reviewStatus = ""
            boardValidationStatus = ""

            let validationStartedAt = Date()
            if dictionary == nil, isDictionaryCacheAvailable {
                status = "Validating board..."
                do {
                    _ = try await loadCachedSolverForUse()
                } catch {
                    boardValidationStatus = boardValidationWaitingText()
                }
            }

            refreshReviewCells()
            applyDictionaryRepairsIfPossible()
            detectedTileCount = board.allCells.filter { !$0.isEmpty }.count
            refreshBoardValidation()
            let validationSeconds = Date().timeIntervalSince(validationStartedAt)
            lastBoardReadTiming = StatusTextFormatter.boardReadTimingText(
                importSeconds: importSeconds,
                ocrSeconds: ocrSeconds,
                validationSeconds: validationSeconds,
                totalSeconds: Date().timeIntervalSince(totalStartedAt)
            )
            screen = .boardCorrection
            warmDictionaryForBoardReviewIfAvailable()
        } catch {
            board = Board(bonuses: bonuses)
            lastCellReads = []
            manuallyCorrectedCellKeys = []
            selectedCorrectionTarget = nil
            detectedTileCount = 0
            autoRepairStatus = ""
            autoRepairItems = []
            ocrReviewItems = []
            autoRepairedCellKeys = []
            reviewCellKeys = []
            invalidWordCellKeys = []
            invalidBoardWords = []
            reviewStatus = ""
            boardValidationStatus = "Board could not be read automatically."
            lastBoardReadTiming = ""
            screen = .boardCorrection
            errorMessage = error.localizedDescription
        }
    }

    func applyCorrections() {
        do {
            let correctedKeys = try correctionCellKeys(from: correctionsText)
            board = try BoardCorrectionParser.applyCorrections(to: board, input: correctionsText)
            manuallyCorrectedCellKeys.formUnion(correctedKeys)
            correctionsText = ""
            selectedCorrectionTarget = nil
            detectedTileCount = board.allCells.filter { !$0.isEmpty }.count
            removeAutoRepairMarkers(for: correctedKeys)
            refreshReviewCells()
            refreshBoardValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendCorrection(row: Int, column: Int) {
        selectedCorrectionTarget = CorrectionTarget(row: row, column: column, coordinate: coordinate(row, column))
        appendCorrections([(row: row, column: column)])
    }

    func appendCorrections(_ coordinates: [(row: Int, column: Int)]) {
        if let first = coordinates.first {
            selectedCorrectionTarget = CorrectionTarget(
                row: first.row,
                column: first.column,
                coordinate: coordinate(first.row, first.column)
            )
        }

        let entries = coordinates.map { correctionEntry(row: $0.row, column: $0.column) }
        guard !entries.isEmpty else { return }

        if correctionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            correctionsText = entries.joined(separator: ", ")
        } else {
            correctionsText += ", \(entries.joined(separator: ", "))"
        }
    }

    func setSelectedCorrectionValue(_ value: String) {
        guard let target = selectedCorrectionTarget else { return }

        let replacement = "\(target.coordinate)=\(value)"
        let parts = correctionsText
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.isEmpty else {
            correctionsText = replacement
            return
        }

        if let lastMatchingIndex = parts.indices.reversed().first(where: { parts[$0].hasPrefix("\(target.coordinate)=") }) {
            var updated = parts
            updated[lastMatchingIndex] = replacement
            correctionsText = updated.filter { !$0.isEmpty }.joined(separator: ", ")
        } else if correctionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            correctionsText = replacement
        } else {
            correctionsText += ", \(replacement)"
        }
    }

    func solve() {
        isBusy = true
        status = "Solving..."
        lastSolveTiming = ""

        Task {
            do {
                let rack = try Rack.parse(rackText)
                let solverWasLive = solver != nil
                let totalStartedAt = Date()
                let solverLoadStartedAt = Date()
                let loadedSolver = try await solverForUse()
                let solverLoadSeconds = Date().timeIntervalSince(solverLoadStartedAt)
                let currentBoard = board
                status = "Finding moves..."
                let solveStartedAt = Date()
                let moves = try await Task.detached {
                    try loadedSolver.findBestMoves(board: currentBoard, rack: rack, limit: 50)
                }.value
                let solveSeconds = Date().timeIntervalSince(solveStartedAt)
                let totalSeconds = Date().timeIntervalSince(totalStartedAt)
                await MainActor.run {
                    results = moves.sorted { lhs, rhs in
                        if lhs.score != rhs.score { return lhs.score > rhs.score }
                        return lhs.word < rhs.word
                    }
                    lastSolveTiming = StatusTextFormatter.solveTimingText(
                        solverWasLive: solverWasLive,
                        solverLoadSeconds: solverLoadSeconds,
                        solveSeconds: solveSeconds,
                        totalSeconds: totalSeconds
                    )
                    selectedMove = results.first
                    screen = .results
                    isBusy = false
                    status = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isBusy = false
                    status = ""
                }
            }
        }
    }

    func finish() {
        board = Board(bonuses: bonuses)
        correctionsText = ""
        selectedCorrectionTarget = nil
        rackText = ""
        results = []
        selectedMove = nil
        detectedTileCount = 0
        autoRepairStatus = ""
        autoRepairItems = []
        ocrReviewItems = []
        autoRepairedCellKeys = []
        reviewCellKeys = []
        invalidWordCellKeys = []
        invalidBoardWords = []
        reviewStatus = ""
        boardValidationStatus = ""
        lastBoardReadTiming = ""
        lastDictionaryLoadTiming = ""
        lastCellReads = []
        manuallyCorrectedCellKeys = []
        screen = .home
    }

    private func startDictionaryLoad() {
        guard solver == nil, solverLoadTask == nil, !isDictionaryLoading else { return }
        dictionaryStatus = "Loading dictionary..."
        lastDictionaryLoadTiming = ""
        isDictionaryLoading = true

        let values = letterValues
        let task = Task.detached {
            let startedAt = Date()
            let cacheDirectory = try dictionaryCacheDirectory()
            let loaded = try BundledDataLoader.loadDictionaryWithCache(cacheDirectory: cacheDirectory)
            return SolverLoadResult(
                dictionary: loaded.dictionary,
                solver: MoveSolver(dictionary: loaded.dictionary, letterValues: values),
                sourceKind: loaded.sourceKind,
                usedCache: loaded.usedCache,
                loadSeconds: Date().timeIntervalSince(startedAt)
            )
        }
        solverLoadTask = task

        Task {
            do {
                let loaded = try await task.value
                dictionary = loaded.dictionary
                solver = loaded.solver
                isDictionaryReady = true
                isDictionaryCacheAvailable = loaded.sourceKind == .full
                isDictionaryLoading = false
                dictionaryStatus = loaded.statusText
                lastDictionaryLoadTiming = loaded.timingText
                applyDictionaryRepairsIfPossible()
                refreshBoardValidation()
                solverLoadTask = nil
            } catch {
                let fallback = PolishWordDictionary.fromWords(["ALA", "KOT", "DOM"])
                dictionary = fallback
                solver = MoveSolver(dictionary: fallback, letterValues: values)
                isDictionaryReady = true
                isDictionaryCacheAvailable = false
                isDictionaryLoading = false
                dictionaryStatus = "Fallback dictionary loaded"
                lastDictionaryLoadTiming = ""
                errorMessage = error.localizedDescription
                solverLoadTask = nil
            }
        }
    }

    private func refreshDictionaryCacheAvailability() {
        Task {
            do {
                let hasCache = try await Task.detached {
                    let cacheDirectory = try dictionaryCacheDirectory()
                    return try BundledDataLoader.hasDictionaryCache(cacheDirectory: cacheDirectory)
                }.value

                isDictionaryCacheAvailable = hasCache
                if hasCache, solver == nil {
                    dictionaryStatus = "Dictionary cache available"
                    warmDictionaryForBoardReviewIfAvailable()
                }
            } catch {
                isDictionaryCacheAvailable = false
            }
        }
    }

    private func loadCachedSolverForUse() async throws -> MoveSolver {
        if let solver {
            return solver
        }

        guard isDictionaryCacheAvailable else {
            throw ScrabblerError.dictionaryNotLoaded
        }

        let values = letterValues
        let loaded = try await Task.detached {
            let startedAt = Date()
            let cacheDirectory = try dictionaryCacheDirectory()
            guard let cached = try BundledDataLoader.loadDictionaryFromCacheIfAvailable(
                cacheDirectory: cacheDirectory
            ) else {
                throw ScrabblerError.dictionaryNotLoaded
            }

            return SolverLoadResult(
                dictionary: cached.dictionary,
                solver: MoveSolver(dictionary: cached.dictionary, letterValues: values),
                sourceKind: cached.sourceKind,
                usedCache: cached.usedCache,
                loadSeconds: Date().timeIntervalSince(startedAt)
            )
        }.value

        dictionary = loaded.dictionary
        solver = loaded.solver
        isDictionaryReady = true
        dictionaryStatus = loaded.statusText
        lastDictionaryLoadTiming = loaded.timingText
        applyDictionaryRepairsIfPossible()
        refreshBoardValidation()
        return loaded.solver
    }

    private func warmDictionaryForBoardReviewIfAvailable() {
        guard !board.isEmpty, !lastCellReads.isEmpty, solver == nil, isDictionaryCacheAvailable else {
            return
        }

        boardValidationStatus = "Loading dictionary for board validation..."
        Task {
            do {
                _ = try await loadCachedSolverForUse()
            } catch {
                boardValidationStatus = boardValidationWaitingText()
            }
        }
    }

    private func solverForUse() async throws -> MoveSolver {
        if let solver {
            return solver
        }

        return try await loadCachedSolverForUse()
    }

    private func applyDictionaryRepairsIfPossible() {
        guard let dictionary, !board.isEmpty, !lastCellReads.isEmpty else {
            return
        }

        let repaired = DictionaryBoardRepairer(dictionary: dictionary, letterValues: letterValues)
            .repair(BoardReadResult(board: board, cells: lastCellReads))
        guard !repaired.appliedRepairs.isEmpty else {
            return
        }

        board = repaired.board
        lastCellReads = repaired.cells
        autoRepairedCellKeys = Set(repaired.appliedRepairs.map { Self.cellKey(row: $0.row, column: $0.column) })
        autoRepairItems = repaired.appliedRepairs
            .map { repair in
                AutoRepairReviewItem(
                    row: repair.row,
                    column: repair.column,
                    coordinate: coordinate(repair.row, repair.column),
                    originalLetter: repair.originalLetter,
                    repairedLetter: repair.repairedLetter,
                    reason: repair.reason
                )
            }
            .sorted {
                if $0.row != $1.row { return $0.row < $1.row }
                return $0.column < $1.column
            }
        autoRepairStatus = repaired.appliedRepairs
            .map { repair in
                let from = repair.originalLetter.map(String.init) ?? "."
                let to = repair.repairedLetter.map(String.init) ?? "."
                return "\(coordinate(repair.row, repair.column)) \(from)→\(to)"
            }
            .joined(separator: ", ")
        refreshReviewCells()
    }

    private func refreshReviewCells() {
        let repairedKeys = autoRepairedCellKeys.union(manuallyCorrectedCellKeys)
        let cellsToReview = BoardReadDiagnostics.reviewCells(
            in: lastCellReads,
            letterValues: letterValues,
            ignoringCellKeys: repairedKeys
        )

        reviewCellKeys = Set(cellsToReview.map { Self.cellKey(row: $0.row, column: $0.column) })
        ocrReviewItems = cellsToReview.map { cell in
            OCRReviewItem(
                row: cell.row,
                column: cell.column,
                coordinate: coordinate(cell.row, cell.column),
                letter: cell.letter,
                confidence: cell.confidence,
                candidates: cell.candidates,
                detectedScoreDigit: cell.detectedScoreDigit,
                reason: reviewReason(for: cell)
            )
        }

        guard !cellsToReview.isEmpty else {
            reviewStatus = ""
            return
        }

        let preview = cellsToReview
            .prefix(10)
            .map { cell -> String in
                let letter = cell.letter.map(String.init) ?? "."
                let candidates = cell.candidates.prefix(3).map(String.init).joined(separator: "/")
                if candidates.isEmpty {
                    return "\(coordinate(cell.row, cell.column))=\(letter)"
                }
                return "\(coordinate(cell.row, cell.column))=\(letter) (\(candidates))"
            }
            .joined(separator: ", ")
        let suffix = cellsToReview.count > 10 ? "…" : ""
        reviewStatus = "Check amber cells: \(preview)\(suffix)"
    }

    private func reviewReason(for cell: CellReview) -> String {
        switch cell.reason {
        case .scoreDigitMismatch(let detected, let expected):
            let letter = cell.letter.map(String.init) ?? "."
            return "value \(detected), \(letter)=\(expected)"
        case .possibleMissedTile:
            return "possible missed tile"
        case .lowConfidence:
            return "low confidence \(StatusTextFormatter.percent(cell.confidence))"
        case .closeCandidates:
            return "close candidates"
        }
    }

    private func refreshBoardValidation() {
        guard !board.isEmpty else {
            invalidWordCellKeys = []
            invalidBoardWords = []
            boardValidationStatus = ""
            return
        }

        guard let dictionary else {
            invalidWordCellKeys = []
            invalidBoardWords = []
            boardValidationStatus = boardValidationWaitingText()
            return
        }

        let words = BoardWordExtractor.extractWords(from: board)
        guard !words.isEmpty else {
            invalidWordCellKeys = []
            invalidBoardWords = []
            boardValidationStatus = "No complete board words detected yet."
            return
        }

        let invalidWords = words.filter { !dictionary.contains($0.text) }
        if invalidWords.isEmpty {
            invalidWordCellKeys = []
            invalidBoardWords = []
            boardValidationStatus = "All detected board words are in the dictionary."
        } else {
            invalidWordCellKeys = Set(invalidWords.flatMap { word in
                word.coordinates.map { Self.cellKey(row: $0.row, column: $0.column) }
            })
            invalidBoardWords = invalidWords.map { word in
                InvalidBoardWord(
                    text: word.text,
                    coordinate: coordinate(word.coordinates[0].row, word.coordinates[0].column),
                    coordinates: word.coordinates
                )
            }
            let preview = invalidWords
                .prefix(8)
                .map { "\($0.text) \(coordinate($0.coordinates[0].row, $0.coordinates[0].column))" }
                .joined(separator: ", ")
            let suffix = invalidWords.count > 8 ? "…" : ""
            boardValidationStatus = "Check words: \(preview)\(suffix)"
        }
    }

    private func coordinate(_ row: Int, _ column: Int) -> String {
        BoardCoordinateFormatter.coordinate(row: row, column: column)
    }

    private func correctionEntry(row: Int, column: Int) -> String {
        "\(coordinate(row, column))="
    }

    private func correctionCellKeys(from input: String) throws -> Set<String> {
        var keys: Set<String> = []
        for item in input.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !item.isEmpty {
            let parts = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let coordinate = parts.first else {
                throw ScrabblerError.invalidCorrection(item)
            }
            let parsed = try BoardCorrectionParser.parseCoordinate(coordinate)
            keys.insert(Self.cellKey(row: parsed.row, column: parsed.column))
        }
        return keys
    }

    private func removeAutoRepairMarkers(for correctedKeys: Set<String>) {
        guard !correctedKeys.isEmpty else { return }

        autoRepairedCellKeys.subtract(correctedKeys)
        autoRepairItems.removeAll { item in
            correctedKeys.contains(Self.cellKey(row: item.row, column: item.column))
        }
        autoRepairStatus = autoRepairItems
            .map { item in
                let from = item.originalLetter.map(String.init) ?? "."
                let to = item.repairedLetter.map(String.init) ?? "."
                return "\(item.coordinate) \(from)→\(to)"
            }
            .joined(separator: ", ")
    }

    private static func cellKey(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }

    private func boardValidationWaitingText() -> String {
        StatusTextFormatter.boardValidationWaitingText(
            isDictionaryLoading: isDictionaryLoading,
            hasSolverLoadTask: solverLoadTask != nil,
            isDictionaryCacheAvailable: isDictionaryCacheAvailable
        )
    }
}

private struct SolverLoadResult: Sendable {
    let dictionary: PolishWordDictionary
    let solver: MoveSolver
    let sourceKind: DictionarySourceKind
    let usedCache: Bool
    let loadSeconds: TimeInterval

    var statusText: String {
        switch (sourceKind, usedCache) {
        case (.full, true):
            "Full dictionary loaded from cache"
        case (.full, false):
            "Full dictionary loaded and cached"
        case (.sample, _):
            "Sample dictionary loaded"
        }
    }

    var timingText: String {
        StatusTextFormatter.dictionaryTimingText(loadSeconds: loadSeconds)
    }
}

private func dictionaryCacheDirectory() throws -> URL {
    let base = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    return base.appendingPathComponent("Scrabbler/DictionaryCache", isDirectory: true)
}
