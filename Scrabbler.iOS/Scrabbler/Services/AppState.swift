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
    @Published var isBusy = false
    @Published var status = ""
    @Published var dictionaryStatus = ""
    @Published var isDictionaryReady = false
    @Published var errorMessage: String?

    private let bonuses: [[BonusType]]
    private let reader: BoardImageReading
    private let letterValues: [Character: Int]
    private var solver: MoveSolver?
    private var solverLoadTask: Task<SolverLoadResult, Error>?

    init() {
        let loadedBonuses = (try? BundledDataLoader.loadBonusLayout()) ??
            Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size)
        let loadedValues = (try? BundledDataLoader.loadLetterValues()) ?? [:]

        self.bonuses = loadedBonuses
        self.board = Board(bonuses: loadedBonuses)
        self.reader = NativeBoardImageReader()
        self.letterValues = loadedValues
        self.dictionaryStatus = "Dictionary not loaded"
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
            correctionsText = ""
            screen = .boardCorrection
        } catch {
            board = Board(bonuses: bonuses)
            screen = .boardCorrection
            errorMessage = error.localizedDescription
        }
    }

    func applyCorrections() {
        do {
            board = try BoardCorrectionParser.applyCorrections(to: board, input: correctionsText)
            correctionsText = ""
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

        Task {
            do {
                let rack = try Rack.parse(rackText)
                let loadedSolver = try await solverForUse()
                let currentBoard = board
                let moves = try await Task.detached {
                    try loadedSolver.findBestMoves(board: currentBoard, rack: rack, limit: 50)
                }.value
                await MainActor.run {
                    results = moves.sorted { lhs, rhs in
                        if lhs.score != rhs.score { return lhs.score > rhs.score }
                        return lhs.word < rhs.word
                    }
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
        screen = .home
    }

    private func startDictionaryLoad() {
        guard solverLoadTask == nil else { return }
        dictionaryStatus = "Loading dictionary..."

        let values = letterValues
        let task = Task.detached {
            let cacheDirectory = try dictionaryCacheDirectory()
            let loaded = try BundledDataLoader.loadDictionaryWithCache(cacheDirectory: cacheDirectory)
            return SolverLoadResult(
                solver: MoveSolver(dictionary: loaded.dictionary, letterValues: values),
                sourceKind: loaded.sourceKind,
                usedCache: loaded.usedCache
            )
        }
        solverLoadTask = task

        Task {
            do {
                let loaded = try await task.value
                solver = loaded.solver
                isDictionaryReady = true
                dictionaryStatus = loaded.statusText
            } catch {
                let fallback = PolishWordDictionary.fromWords(["ALA", "KOT", "DOM"])
                solver = MoveSolver(dictionary: fallback, letterValues: values)
                isDictionaryReady = true
                dictionaryStatus = "Fallback dictionary loaded"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func solverForUse() async throws -> MoveSolver {
        if let solver {
            return solver
        }

        startDictionaryLoad()
        guard let solverLoadTask else {
            throw ScrabblerError.emptyDictionary
        }

        let loaded = try await solverLoadTask.value
        solver = loaded.solver
        isDictionaryReady = true
        dictionaryStatus = loaded.statusText
        return loaded.solver
    }
}

private struct SolverLoadResult: Sendable {
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
