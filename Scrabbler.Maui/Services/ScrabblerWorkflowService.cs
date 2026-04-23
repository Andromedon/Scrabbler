using Scrabbler.Data;
using Scrabbler.Domain.BoardModel;
using Scrabbler.ImageAnalysis;
using Scrabbler.Solver;

namespace Scrabbler.Maui.Services;

public sealed class ScrabblerWorkflowService
{
    private readonly MauiAssetService _assets;
    private readonly ScrabblerSession _session;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private IBoardImageReader? _reader;
    private IReadOnlyDictionary<char, int>? _letterValues;
    private IMoveSolver? _solver;

    public ScrabblerWorkflowService(MauiAssetService assets, ScrabblerSession session)
    {
        _assets = assets;
        _session = session;
    }

    public async Task ReadBoardAsync(string imagePath, CancellationToken cancellationToken = default)
    {
        await EnsureReaderAsync(cancellationToken);
        var result = await Task.Run(() => _reader!.ReadAsync(imagePath), cancellationToken);
        _session.ImagePath = imagePath;
        _session.Board = result.Board;
        _session.Cells = result.Cells;
        _session.Moves = Array.Empty<Move>();
        _session.AssetWarning = _assets.Warning;
    }

    public void ApplyCorrections(string corrections)
    {
        if (_session.Board is null)
        {
            throw new InvalidOperationException("Read a board before applying corrections.");
        }

        _session.Board = BoardCorrectionParser.ApplyCorrections(_session.Board, corrections);
    }

    public IReadOnlyList<Move> Solve(string rackText, int limit = 10)
    {
        if (_session.Board is null)
        {
            throw new InvalidOperationException("Read a board before solving.");
        }

        EnsureSolver();
        var rack = Rack.Parse(rackText);
        var moves = _solver!.FindBestMoves(_session.Board, rack, limit)
            .OrderByDescending(move => move.Score)
            .ToArray();
        _session.Rack = rack;
        _session.Moves = moves;
        return moves;
    }

    private async Task EnsureReaderAsync(CancellationToken cancellationToken)
    {
        if (_reader is not null)
        {
            return;
        }

        await _lock.WaitAsync(cancellationToken);
        try
        {
            if (_reader is not null)
            {
                return;
            }

            await _assets.EnsureAsync(cancellationToken);
            var bonuses = BonusLayoutLoader.Load(_assets.BonusLayoutPath);
            _letterValues = LetterValuesLoader.Load(_assets.LetterValuesPath);
            _reader = new ImageSharpScreenshotBoardImageReader(bonuses, _letterValues, _assets.LetterSamplesPath);
        }
        finally
        {
            _lock.Release();
        }
    }

    private void EnsureSolver()
    {
        if (_solver is not null)
        {
            return;
        }

        _assets.EnsureAsync().GetAwaiter().GetResult();
        _letterValues ??= LetterValuesLoader.Load(_assets.LetterValuesPath);
        var dictionary = PolishWordDictionary.Load(
            _assets.DictionaryPath,
            Path.Combine(FileSystem.CacheDirectory, "DictionaryCache"));
        _solver = new MoveSolver(dictionary, _letterValues);
    }
}
