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
    @Published var errorMessage: String?

    private let bonuses: [[BonusType]]
    private let reader: BoardImageReading
    private let dictionary: PolishWordDictionary
    private let solver: MoveSolver

    init() {
        let loadedBonuses = (try? BundledDataLoader.loadBonusLayout()) ??
            Array(repeating: Array(repeating: BonusType.none, count: Board.size), count: Board.size)
        let loadedDictionary = (try? BundledDataLoader.loadSampleDictionary()) ??
            PolishWordDictionary.fromWords(["ALA", "KOT", "DOM"])
        let loadedValues = (try? BundledDataLoader.loadLetterValues()) ?? [:]

        self.bonuses = loadedBonuses
        self.board = Board(bonuses: loadedBonuses)
        self.reader = NativeBoardImageReader()
        self.dictionary = loadedDictionary
        self.solver = MoveSolver(dictionary: loadedDictionary, letterValues: loadedValues)
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
                let moves = try solver.findBestMoves(board: board, rack: rack, limit: 50)
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
}
