using Scrabbler.Data;
using Scrabbler.Domain.BoardModel;
using Scrabbler.ImageAnalysis;
using Scrabbler.Solver;
using System.Diagnostics;

namespace Scrabbler.Maui.Services;

public sealed class ScrabblerWorkflowService
{
    private readonly MauiAssetService _assets;
    private readonly ScrabblerSession _session;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private readonly object _backgroundWarmupLock = new();
    private IBoardImageReader? _reader;
    private IReadOnlyDictionary<char, int>? _letterValues;
    private IWordDictionary? _dictionary;
    private IMoveSolver? _solver;
    private Task? _backgroundWarmupTask;

    public ScrabblerWorkflowService(MauiAssetService assets, ScrabblerSession session)
    {
        _assets = assets;
        _session = session;
    }

    public async Task ReadBoardAsync(string imagePath, Action<string>? reportStatus = null, CancellationToken cancellationToken = default)
    {
        reportStatus?.Invoke("Preparing board reader...");
        await EnsureReaderAsync(cancellationToken);
        reportStatus?.Invoke("Analyzing board image...");
        var stopwatch = Stopwatch.StartNew();
        var result = await Task.Run(() => _reader!.ReadAsync(imagePath), cancellationToken);
        stopwatch.Stop();
        reportStatus?.Invoke("Validating board words...");
        await EnsureDictionaryAsync(cancellationToken);
        result = await Task.Run(() => new DictionaryBoardRepairer(_dictionary!, _letterValues!).Repair(result), cancellationToken);
        reportStatus?.Invoke("Preparing correction screen...");
        _session.ImagePath = imagePath;
        _session.Board = result.Board;
        _session.Cells = result.Cells;
        _session.Repairs = result.Repairs ?? Array.Empty<BoardRepair>();
        _session.Moves = Array.Empty<Move>();
        _session.AssetWarning = _assets.Warning;
        _session.Performance = _session.Performance with { BoardRead = stopwatch.Elapsed };
        StartWarmDictionaryInBackground();
    }

    public void ApplyCorrections(string corrections)
    {
        if (_session.Board is null)
        {
            throw new InvalidOperationException("Read a board before applying corrections.");
        }

        _session.Board = BoardCorrectionParser.ApplyCorrections(_session.Board, corrections);
    }

    public async Task<IReadOnlyList<Move>> SolveAsync(string rackText, int limit = 10, CancellationToken cancellationToken = default)
    {
        if (_session.Board is null)
        {
            throw new InvalidOperationException("Read a board before solving.");
        }

        var rack = Rack.Parse(rackText);
        await EnsureSolverAsync(cancellationToken);
        var solveStopwatch = Stopwatch.StartNew();
        var moves = await Task.Run(() => _solver!.FindBestMoves(_session.Board, rack, limit), cancellationToken);
        solveStopwatch.Stop();
        _session.Rack = rack;
        _session.Moves = moves;
        _session.Performance = _session.Performance with { Solve = solveStopwatch.Elapsed };
        return moves;
    }

    public async Task WarmDictionaryAsync(CancellationToken cancellationToken = default)
    {
        await EnsureSolverAsync(cancellationToken);
    }

    public void StartWarmDictionaryInBackground()
    {
        if (_session.Board is null)
        {
            return;
        }

        lock (_backgroundWarmupLock)
        {
            if (_solver is not null)
            {
                return;
            }

            if (_backgroundWarmupTask is { IsCompleted: false })
            {
                return;
            }

            _backgroundWarmupTask = Task.Run(async () =>
            {
                try
                {
                    await WarmDictionaryAsync();
                }
                catch
                {
                    // Ignore background warm-up failures; foreground actions surface them.
                }
            });
        }
    }

    public async Task<bool> IsDictionaryCachedAsync(CancellationToken cancellationToken = default)
    {
        await _assets.EnsureAsync(cancellationToken);
        var cacheDirectory = Path.Combine(FileSystem.CacheDirectory, "DictionaryCache");
        return Directory.Exists(cacheDirectory)
            && Directory.EnumerateFileSystemEntries(cacheDirectory).Any();
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

            var assetResult = await _assets.EnsureAsync(cancellationToken);
            var bonuses = BonusLayoutLoader.Load(_assets.BonusLayoutPath);
            _letterValues = LetterValuesLoader.Load(_assets.LetterValuesPath);
            _reader = new ImageSharpScreenshotBoardImageReader(bonuses, _letterValues, _assets.LetterSamplesPath);
            _session.Performance = _session.Performance with
            {
                AssetPreparation = assetResult.Elapsed
            };
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task EnsureSolverAsync(CancellationToken cancellationToken)
    {
        if (_solver is not null)
        {
            return;
        }

        await EnsureDictionaryAsync(cancellationToken);
        await _lock.WaitAsync(cancellationToken);
        try
        {
            if (_solver is not null)
            {
                return;
            }

            var solverStopwatch = Stopwatch.StartNew();
            _solver = new MoveSolver(_dictionary!, _letterValues!);
            solverStopwatch.Stop();
            _session.Performance = _session.Performance with
            {
                SolverConstruction = solverStopwatch.Elapsed,
                DictionaryReady = true
            };
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task EnsureDictionaryAsync(CancellationToken cancellationToken)
    {
        if (_dictionary is not null)
        {
            return;
        }

        await _lock.WaitAsync(cancellationToken);
        try
        {
            if (_dictionary is not null)
            {
                return;
            }

            var assetResult = await _assets.EnsureAsync(cancellationToken);
            _letterValues ??= LetterValuesLoader.Load(_assets.LetterValuesPath);
            var cacheDirectory = Path.Combine(FileSystem.CacheDirectory, "DictionaryCache");
            var cacheWasWarm = Directory.Exists(cacheDirectory)
                && Directory.EnumerateFileSystemEntries(cacheDirectory).Any();
            var dictionaryStopwatch = Stopwatch.StartNew();
            _dictionary = await Task.Run(() => PolishWordDictionary.Load(
                _assets.DictionaryPath,
                cacheDirectory), cancellationToken);
            dictionaryStopwatch.Stop();
            _session.Performance = _session.Performance with
            {
                AssetPreparation = assetResult.Elapsed,
                DictionaryLoad = dictionaryStopwatch.Elapsed,
                DictionaryCacheWarm = cacheWasWarm,
                DictionaryReady = true
            };
        }
        finally
        {
            _lock.Release();
        }
    }
}
