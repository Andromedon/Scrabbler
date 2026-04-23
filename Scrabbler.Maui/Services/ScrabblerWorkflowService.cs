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
    private IMoveSolver? _solver;

    public ScrabblerWorkflowService(MauiAssetService assets, ScrabblerSession session)
    {
        _assets = assets;
        _session = session;
    }

    public async Task ReadBoardAsync(string imagePath, CancellationToken cancellationToken = default)
    {
        await EnsureCoreAsync(cancellationToken);
        var result = await _reader!.ReadAsync(imagePath);
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

        var rack = Rack.Parse(rackText);
        var moves = _solver!.FindBestMoves(_session.Board, rack, limit)
            .OrderByDescending(move => move.Score)
            .ToArray();
        _session.Rack = rack;
        _session.Moves = moves;
        return moves;
    }

    private async Task EnsureCoreAsync(CancellationToken cancellationToken)
    {
        if (_reader is not null && _solver is not null)
        {
            return;
        }

        await _lock.WaitAsync(cancellationToken);
        try
        {
            if (_reader is not null && _solver is not null)
            {
                return;
            }

            await _assets.EnsureAsync(cancellationToken);
            var bonuses = BonusLayoutLoader.Load(_assets.BonusLayoutPath);
            var letterValues = LetterValuesLoader.Load(_assets.LetterValuesPath);
            _reader = new ImageSharpScreenshotBoardImageReader(bonuses, letterValues, _assets.LetterSamplesPath);
            var dictionary = PolishWordDictionary.Load(
                _assets.DictionaryPath,
                Path.Combine(FileSystem.CacheDirectory, "DictionaryCache"));
            _solver = new MoveSolver(dictionary, letterValues);
        }
        finally
        {
            _lock.Release();
        }
    }
}
