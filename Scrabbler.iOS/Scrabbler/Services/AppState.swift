import Foundation
import PhotosUI
import SwiftUI
import ScrabblerKit

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
    @Published var rackText = ""
    @Published var results: [Move] = []
    @Published var selectedMove: Move?
    @Published var detectedTileCount = 0
    @Published var boardValidationStatus = ""
    @Published var autoRepairStatus = ""
    @Published var autoRepairedCellKeys: Set<String> = []
    @Published var isBusy = false
    @Published var status = ""
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
        defer {
            isBusy = false
            status = ""
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not read the selected image."
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("scrabbler-selected-board")
                .appendingPathExtension("jpg")
            try data.write(to: url, options: .atomic)
            let result = try await reader.readBoard(from: url, bonuses: bonuses)
            board = result.board
            lastCellReads = result.cells
            correctionsText = ""
            applyDictionaryRepairsIfPossible()
            detectedTileCount = board.allCells.filter { !$0.isEmpty }.count
            refreshBoardValidation()
            screen = .boardCorrection
            warmDictionaryForBoardReviewIfAvailable()
        } catch {
            board = Board(bonuses: bonuses)
            lastCellReads = []
            detectedTileCount = 0
            autoRepairStatus = ""
            autoRepairedCellKeys = []
            boardValidationStatus = "Board could not be read automatically."
            screen = .boardCorrection
            errorMessage = error.localizedDescription
        }
    }

    func applyCorrections() {
        do {
            board = try BoardCorrectionParser.applyCorrections(to: board, input: correctionsText)
            correctionsText = ""
            detectedTileCount = board.allCells.filter { !$0.isEmpty }.count
            autoRepairStatus = ""
            autoRepairedCellKeys = []
            refreshBoardValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendCorrection(row: Int, column: Int) {
        let coordinate = "\(String(UnicodeScalar(UInt8(ascii: "A") + UInt8(column))))\(row + 1)="
        if correctionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            correctionsText = coordinate
        } else {
            correctionsText += ", \(coordinate)"
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
                    lastSolveTiming = Self.solveTimingText(
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
        rackText = ""
        results = []
        selectedMove = nil
        detectedTileCount = 0
        autoRepairStatus = ""
        autoRepairedCellKeys = []
        boardValidationStatus = ""
        lastCellReads = []
        screen = .home
    }

    private func startDictionaryLoad() {
        guard solver == nil, solverLoadTask == nil, !isDictionaryLoading else { return }
        dictionaryStatus = "Loading dictionary..."
        isDictionaryLoading = true

        let values = letterValues
        let task = Task.detached {
            let cacheDirectory = try dictionaryCacheDirectory()
            let loaded = try BundledDataLoader.loadDictionaryWithCache(cacheDirectory: cacheDirectory)
            return SolverLoadResult(
                dictionary: loaded.dictionary,
                solver: MoveSolver(dictionary: loaded.dictionary, letterValues: values),
                sourceKind: loaded.sourceKind,
                usedCache: loaded.usedCache
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
                usedCache: cached.usedCache
            )
        }.value

        dictionary = loaded.dictionary
        solver = loaded.solver
        isDictionaryReady = true
        dictionaryStatus = loaded.statusText
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
                boardValidationStatus = "Board validation waits for dictionary."
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
        autoRepairStatus = repaired.appliedRepairs
            .map { repair in
                let from = repair.originalLetter.map(String.init) ?? "."
                return "\(coordinate(repair.row, repair.column)) \(from)→\(repair.repairedLetter)"
            }
            .joined(separator: ", ")
    }

    private func refreshBoardValidation() {
        guard !board.isEmpty else {
            boardValidationStatus = ""
            return
        }

        guard let dictionary else {
            boardValidationStatus = "Board validation waits for dictionary."
            return
        }

        let words = BoardWordExtractor.extractWords(from: board)
        guard !words.isEmpty else {
            boardValidationStatus = "No complete board words detected yet."
            return
        }

        let invalidWords = words.filter { !dictionary.contains($0.text) }
        if invalidWords.isEmpty {
            boardValidationStatus = "All detected board words are in the dictionary."
        } else {
            let preview = invalidWords
                .prefix(8)
                .map { "\($0.text) \(coordinate($0.coordinates[0].row, $0.coordinates[0].column))" }
                .joined(separator: ", ")
            let suffix = invalidWords.count > 8 ? "…" : ""
            boardValidationStatus = "Check words: \(preview)\(suffix)"
        }
    }

    private func coordinate(_ row: Int, _ column: Int) -> String {
        "\(String(UnicodeScalar(UInt8(ascii: "A") + UInt8(column))))\(row + 1)"
    }

    private static func cellKey(row: Int, column: Int) -> String {
        "\(row):\(column)"
    }

    private static func solveTimingText(
        solverWasLive: Bool,
        solverLoadSeconds: TimeInterval,
        solveSeconds: TimeInterval,
        totalSeconds: TimeInterval
    ) -> String {
        let source = solverWasLive ? "solver in memory" : "solver loaded from cache"
        return "\(source) · prepare \(formatSeconds(solverLoadSeconds)) · solve \(formatSeconds(solveSeconds)) · total \(formatSeconds(totalSeconds))"
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int((seconds * 1_000).rounded())) ms"
        }

        return String(format: "%.1f s", seconds)
    }
}

private struct SolverLoadResult: Sendable {
    let dictionary: PolishWordDictionary
    let solver: MoveSolver
    let sourceKind: DictionarySourceKind
    let usedCache: Bool

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
