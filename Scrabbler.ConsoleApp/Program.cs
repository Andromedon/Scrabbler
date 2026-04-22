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

Directory.CreateDirectory(settings.InputDirectory);

console.WriteInfo($"Scanning input directory: {settings.InputDirectory}");
var inputProvider = new FixedDirectoryInputImageProvider(settings.InputDirectory);
var selectedImage = inputProvider.GetSelectedImage();
if (selectedImage is null)
{
    console.WriteError($"No board image found. Put a .jpg, .jpeg, .png, .webp, or .bmp file in: {settings.InputDirectory}");
    return;
}

console.WriteInfo($"Using board image: {selectedImage.FullName}");

var bonusLayout = BonusLayoutLoader.Load(settings.BonusLayoutPath);
var letterValues = LetterValuesLoader.Load(settings.LetterValuesPath);

var imageReader = new ImageSharpScreenshotBoardImageReader(bonusLayout);
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
