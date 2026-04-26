using Scrabbler.Domain.BoardModel;
using Scrabbler.ImageAnalysis;
using Scrabbler.Solver;

namespace Scrabbler.Maui.Services;

public sealed class ScrabblerSession
{
    public sealed record PerformanceSnapshot(
        TimeSpan? AssetPreparation = null,
        TimeSpan? ImageImport = null,
        TimeSpan? BoardRead = null,
        TimeSpan? DictionaryLoad = null,
        TimeSpan? SolverConstruction = null,
        TimeSpan? Solve = null,
        bool DictionaryCacheWarm = false,
        bool DictionaryReady = false);

    public string? ImagePath { get; set; }

    public Board? Board { get; set; }

    public IReadOnlyList<CellRead> Cells { get; set; } = Array.Empty<CellRead>();

    public IReadOnlyList<BoardRepair> Repairs { get; set; } = Array.Empty<BoardRepair>();

    public Rack? Rack { get; set; }

    public IReadOnlyList<Move> Moves { get; set; } = Array.Empty<Move>();

    public string? AssetWarning { get; set; }

    public PerformanceSnapshot Performance { get; set; } = new();

    public void Clear()
    {
        ImagePath = null;
        Board = null;
        Cells = Array.Empty<CellRead>();
        Repairs = Array.Empty<BoardRepair>();
        Rack = null;
        Moves = Array.Empty<Move>();
        AssetWarning = null;
        Performance = new();
    }
}
