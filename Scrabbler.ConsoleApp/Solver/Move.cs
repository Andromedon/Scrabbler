using Scrabbler.App.BoardModel;

namespace Scrabbler.App.Solver;

public sealed record Move(
    string Word,
    int Row,
    int Column,
    Direction Direction,
    IReadOnlyList<PlacedTile> PlacedTiles,
    int Score,
    IReadOnlyList<string> CrossWords);
