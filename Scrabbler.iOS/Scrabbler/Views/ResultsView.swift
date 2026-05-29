import SwiftUI
import ScrabblerKit

struct ResultsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            if let selected = state.selectedMove {
                MovePreviewView(move: selected)
                    .environmentObject(state)
                    .frame(maxHeight: 260)
            }

            List(state.results, id: \.word) { move in
                Button {
                    state.selectedMove = move
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(move.score)")
                                .font(.headline.monospacedDigit())
                            Text(move.word)
                                .font(.headline)
                            Spacer()
                            Text("\(coordinate(move.row, move.column)) \(move.direction == .horizontal ? "→" : "↓")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Placed: \(move.placedTiles.map { "\($0.letter)\(coordinate($0.row, $0.column))" }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Finish") {
                state.finish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom)
        }
        .navigationTitle("Results")
    }

    private func coordinate(_ row: Int, _ column: Int) -> String {
        "\(String(UnicodeScalar(UInt8(ascii: "A") + UInt8(column))))\(row + 1)"
    }
}

struct MovePreviewView: View {
    @EnvironmentObject private var state: AppState
    let move: Move

    var body: some View {
        BoardGridView(board: previewBoard()) { _, _ in }
    }

    private func previewBoard() -> Board {
        var board = state.board
        for tile in move.placedTiles {
            board = board.setCell(row: tile.row, column: tile.column, letter: tile.letter, isBlank: tile.isBlank)
        }
        return board
    }
}
