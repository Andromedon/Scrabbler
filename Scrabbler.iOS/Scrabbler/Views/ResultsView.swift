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
                MoveDetailView(move: selected)
                    .padding(.horizontal)
            }

            if !state.lastSolveTiming.isEmpty {
                Text(state.lastSolveTiming)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if state.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No moves found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.results, id: \.stableID) { move in
                    Button {
                        state.selectedMove = move
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(move.score)")
                                    .font(.headline.monospacedDigit())
                                    .frame(minWidth: 38, alignment: .leading)
                                Text(move.word)
                                    .font(.headline)
                                Spacer()
                                Text(MoveFormatter.coordinateDirectionText(move))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(MoveFormatter.placedTilesLabelText(move))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !move.crossWords.isEmpty {
                                Text(MoveFormatter.crossWordsLabelText(move))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(state.selectedMove?.stableID == move.stableID ? Color.accentColor.opacity(0.14) : Color.clear)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    state.screen = .rackInput
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }

}

private struct MoveDetailView: View {
    let move: Move

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(move.score)")
                    .font(.headline.monospacedDigit())
                Text(move.word)
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(MoveFormatter.coordinateDirectionText(move))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(MoveFormatter.placedTilesLabelText(move))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(MoveFormatter.crossWordsLabelText(move))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

}

struct MovePreviewView: View {
    @EnvironmentObject private var state: AppState
    let move: Move

    var body: some View {
        BoardGridView(board: state.board.applying(move), highlightedCells: highlightedCells()) { _, _ in }
    }

    private func highlightedCells() -> Set<String> {
        Set(move.placedTiles.map { BoardGridView.key(row: $0.row, column: $0.column) })
    }
}

private extension Move {
    var stableID: String {
        MoveFormatter.stableID(self)
    }
}
