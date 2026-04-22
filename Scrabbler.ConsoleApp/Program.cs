using Microsoft.Extensions.Configuration;
using Scrabbler.App.Configuration;
using Scrabbler.App.ConsoleUi;
using Scrabbler.App.Data;
using Scrabbler.App.ImageAnalysis;
using Scrabbler.App.Solver;

var baseDirectory = AppContext.BaseDirectory;
var workingDirectory = Directory.GetCurrentDirectory();
var contentRoot = AppSettings.FindContentRoot(workingDirectory, baseDirectory);
var configuration = new ConfigurationBuilder()
    .SetBasePath(contentRoot)
    .AddJsonFile("appsettings.json", optional: true)
    .AddJsonFile(Path.Combine(workingDirectory, "appsettings.json"), optional: true)
    .Build();

var settings = AppSettings.From(configuration, baseDirectory, workingDirectory);
var console = new ScrabblerConsole();

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

var inputProvider = InputImageProviderFactory.Create(settings);
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

var bonusLayout = BonusLayoutLoader.Load(settings.BonusLayoutPath);
var letterValues = LetterValuesLoader.Load(settings.LetterValuesPath);

var imageReader = new ImageSharpScreenshotBoardImageReader(bonusLayout, letterValues);
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
var dictionary = PolishWordDictionary.Load(
    settings.DictionaryPath,
    Path.Combine(settings.ContentRoot, "Cache"),
    console.WriteInfo);
var solver = new MoveSolver(dictionary, letterValues);
var moves = solver.FindBestMoves(board, rack, limit: 10);

if (moves.Count == 0)
{
    console.WriteError("No legal move found for this rack and board.");
    return;
}

console.WriteBestMoves(moves);
