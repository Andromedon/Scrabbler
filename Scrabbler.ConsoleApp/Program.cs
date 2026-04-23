using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Scrabbler.App.Configuration;
using Scrabbler.App.ConsoleUi;
using Scrabbler.App.ImageAnalysis;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Data;
using Scrabbler.ImageAnalysis;
using Scrabbler.Input;
using Scrabbler.Solver;

var baseDirectory = AppContext.BaseDirectory;
var workingDirectory = Directory.GetCurrentDirectory();
var contentRoot = AppSettings.FindContentRoot(workingDirectory, baseDirectory);
var configuration = new ConfigurationBuilder()
    .SetBasePath(contentRoot)
    .AddJsonFile("appsettings.json", optional: true)
    .AddJsonFile(Path.Combine(workingDirectory, "appsettings.json"), optional: true)
    .Build();

var settings = AppSettings.From(configuration, baseDirectory, workingDirectory);
var services = new ServiceCollection()
    .AddSingleton(settings)
    .AddSingleton<ScrabblerConsole>()
    .AddSingleton<IInputImageProvider>(_ => InputImageProviderFactory.Create(settings))
    .AddSingleton(_ => BonusLayoutLoader.Load(settings.BonusLayoutPath))
    .AddSingleton<IReadOnlyDictionary<char, int>>(_ => LetterValuesLoader.Load(settings.LetterValuesPath))
    .AddSingleton<IBoardImageReader>(provider => new ImageSharpScreenshotBoardImageReader(
        provider.GetRequiredService<BonusType[,]>(),
        provider.GetRequiredService<IReadOnlyDictionary<char, int>>(),
        settings.LetterSamplesPath))
    .AddSingleton<IWordDictionary>(provider => PolishWordDictionary.Load(
        settings.DictionaryPath,
        Path.Combine(settings.ContentRoot, "Cache"),
        provider.GetRequiredService<ScrabblerConsole>().WriteInfo))
    .AddSingleton<IMoveSolver>(provider => new MoveSolver(
        provider.GetRequiredService<IWordDictionary>(),
        provider.GetRequiredService<IReadOnlyDictionary<char, int>>()))
    .BuildServiceProvider();

var console = services.GetRequiredService<ScrabblerConsole>();

if (settings.InputSource == InputSource.Local)
{
    Directory.CreateDirectory(settings.InputDirectory);
    console.WriteInfo("Input source: local directory");
    console.WriteInfo($"Scanning input directory: {settings.InputDirectory}");
}
else
{
    console.WriteInfo("Input source: Google Drive");
    console.WriteInfo($"Google Drive download directory: {settings.GoogleDriveDownloadDirectory}");
}

var inputProvider = services.GetRequiredService<IInputImageProvider>();
FileInfo? selectedImage;
try
{
    selectedImage = await inputProvider.GetSelectedImageAsync();
}
catch (Exception ex)
{
    console.WriteError($"Input image selection failed: {ex.Message}");
    return;
}

if (selectedImage is null)
{
    if (settings.InputSource == InputSource.Local)
    {
        console.WriteError($"No board image found. Put a .jpg, .jpeg, .png, .webp, or .bmp file in: {settings.InputDirectory}");
    }
    else
    {
        console.WriteError($"No supported board image found in Google Drive folder '{settings.GoogleDriveFolderId}'.");
    }

    return;
}

console.WriteInfo($"Using board image: {selectedImage.FullName}");

var imageReader = services.GetRequiredService<IBoardImageReader>();
BoardReadResult readResult;
try
{
    readResult = await imageReader.ReadAsync(selectedImage.FullName);
}
catch (Exception ex)
{
    console.WriteError($"Image analysis failed: {ex.Message}");
    console.WriteInfo("You can still use this app by improving the screenshot or extending the image reader.");
    return;
}

var board = readResult.Board;
console.WriteInfo("Detected board:");
console.WriteBoard(board);
console.WriteDetectedOccupiedCells(readResult.Cells);

board = console.ApplyBoardCorrections(board);

var rack = console.ReadRack();
var solver = services.GetRequiredService<IMoveSolver>();
var moves = solver.FindBestMoves(board, rack, limit: 10);

if (moves.Count == 0)
{
    console.WriteError("No legal move found for this rack and board.");
    return;
}

console.WriteBestMoves(moves);
