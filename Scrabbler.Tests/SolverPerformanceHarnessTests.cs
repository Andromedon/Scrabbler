using System.Diagnostics;
using Scrabbler.Data;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Solver;

namespace Scrabbler.Tests;

public sealed class SolverPerformanceHarnessTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"scrabbler-perf-{Guid.NewGuid():N}");

    public SolverPerformanceHarnessTests()
    {
        Directory.CreateDirectory(_directory);
    }

    [Fact]
    public void WarmCacheAndWarmSolverProduceSameResults()
    {
        var dictionaryPath = WriteDictionary("KOT", "TOK", "KOTY", "TO", "OK", "ROK", "ROTY");
        var cacheDirectory = Path.Combine(_directory, "cache");
        var board = EmptyBoardWithCenterDoubleWord().SetCell(7, 7, 'O').SetCell(7, 8, 'T');
        var rack = Rack.Parse("KRY");
        var values = Values();

        var coldLoadStopwatch = Stopwatch.StartNew();
        var coldDictionary = PolishWordDictionary.Load(dictionaryPath, cacheDirectory);
        coldLoadStopwatch.Stop();

        var warmLoadStopwatch = Stopwatch.StartNew();
        var warmDictionary = PolishWordDictionary.Load(dictionaryPath, cacheDirectory);
        warmLoadStopwatch.Stop();

        var coldSolver = new MoveSolver(coldDictionary, values);
        var warmSolver = new MoveSolver(warmDictionary, values);

        var coldSolveStopwatch = Stopwatch.StartNew();
        var coldMoves = coldSolver.FindBestMoves(board, rack, 10);
        coldSolveStopwatch.Stop();

        var warmSolveStopwatch = Stopwatch.StartNew();
        var warmMoves = warmSolver.FindBestMoves(board, rack, 10);
        warmSolveStopwatch.Stop();

        var inMemorySolveStopwatch = Stopwatch.StartNew();
        var secondWarmMoves = warmSolver.FindBestMoves(board, rack, 10);
        inMemorySolveStopwatch.Stop();

        AssertEquivalentMoves(coldMoves, warmMoves);
        AssertEquivalentMoves(warmMoves, secondWarmMoves);
        Assert.True(coldLoadStopwatch.Elapsed >= TimeSpan.Zero);
        Assert.True(warmLoadStopwatch.Elapsed >= TimeSpan.Zero);
        Assert.True(coldSolveStopwatch.Elapsed >= TimeSpan.Zero);
        Assert.True(warmSolveStopwatch.Elapsed >= TimeSpan.Zero);
        Assert.True(inMemorySolveStopwatch.Elapsed >= TimeSpan.Zero);
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
    }

    private static void AssertEquivalentMoves(IReadOnlyList<Move> expected, IReadOnlyList<Move> actual)
    {
        Assert.Equal(expected.Count, actual.Count);
        for (var i = 0; i < expected.Count; i++)
        {
            Assert.Equal(expected[i].Word, actual[i].Word);
            Assert.Equal(expected[i].Row, actual[i].Row);
            Assert.Equal(expected[i].Column, actual[i].Column);
            Assert.Equal(expected[i].Direction, actual[i].Direction);
            Assert.Equal(expected[i].Score, actual[i].Score);
            Assert.Equal(expected[i].CrossWords, actual[i].CrossWords);
            Assert.Equal(expected[i].PlacedTiles, actual[i].PlacedTiles);
        }
    }

    private string WriteDictionary(params string[] words)
    {
        var path = Path.Combine(_directory, "dictionary.txt");
        File.WriteAllLines(path, words);
        return path;
    }

    private static Board EmptyBoardWithCenterDoubleWord()
    {
        var bonuses = new BonusType[Board.Size, Board.Size];
        bonuses[7, 7] = BonusType.DoubleWord;
        return new Board(bonuses);
    }

    private static IReadOnlyDictionary<char, int> Values()
    {
        return new Dictionary<char, int>
        {
            ['K'] = 2,
            ['O'] = 1,
            ['R'] = 1,
            ['T'] = 2,
            ['Y'] = 2
        };
    }
}
