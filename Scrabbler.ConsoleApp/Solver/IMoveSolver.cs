using Scrabbler.App.BoardModel;

namespace Scrabbler.App.Solver;

public interface IMoveSolver
{
    IReadOnlyList<Move> FindBestMoves(Board board, Rack rack, int limit);
}
