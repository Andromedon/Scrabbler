using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Solver;

public interface IMoveSolver
{
    IReadOnlyList<Move> FindBestMoves(Board board, Rack rack, int limit);
}
