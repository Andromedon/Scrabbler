import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct LetterCandidate: Equatable, Sendable {
    public let letter: Character
    public let distance: Double
    public let matchedScoreDigit: Int?

    public init(letter: Character, distance: Double, matchedScoreDigit: Int? = nil) {
        self.letter = PolishAlphabet.normalizeLetter(letter)
        self.distance = distance
        self.matchedScoreDigit = matchedScoreDigit
    }
}

public struct CellRead: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let letter: Character?
    public let isBlank: Bool
    public let confidence: Double
    public let candidates: [LetterCandidate]
    public let detectedScoreDigit: Int?

    public init(
        row: Int,
        column: Int,
        letter: Character?,
        isBlank: Bool = false,
        confidence: Double = 0,
        candidates: [LetterCandidate] = [],
        detectedScoreDigit: Int? = nil
    ) {
        self.row = row
        self.column = column
        self.letter = letter.map(PolishAlphabet.normalizeLetter)
        self.isBlank = isBlank
        self.confidence = confidence
        self.candidates = candidates
        self.detectedScoreDigit = detectedScoreDigit
    }
}

public struct BoardReadResult: Equatable, Sendable {
    public let board: Board
    public let cells: [CellRead]
    public let appliedRepairs: [BoardRepair]

    public init(board: Board, cells: [CellRead] = [], appliedRepairs: [BoardRepair] = []) {
        self.board = board
        self.cells = cells
        self.appliedRepairs = appliedRepairs
    }
}

public struct BoardRepair: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let originalLetter: Character?
    public let repairedLetter: Character
    public let reason: String
}

public protocol BoardImageReading: Sendable {
    func readBoard(from imageURL: URL, bonuses: [[BonusType]]) async throws -> BoardReadResult
}

public enum BoardImageReaderError: LocalizedError {
    case imageCouldNotBeLoaded
    case textRecognitionFailed

    public var errorDescription: String? {
        switch self {
        case .imageCouldNotBeLoaded:
            "Could not load the selected board image."
        case .textRecognitionFailed:
            "Could not recognize any board letters in the selected image."
        }
    }
}

public struct NativeBoardImageReader: BoardImageReading {
    public init() {}

    public func readBoard(from imageURL: URL, bonuses: [[BonusType]]) async throws -> BoardReadResult {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BoardImageReaderError.imageCouldNotBeLoaded
        }

        let observations = try recognizeText(in: imageURL)
        let mapper = BoardImageMapper(width: image.width, height: image.height)
        let sampler = BoardColorSampler(image: image, mapper: mapper)

        var readsByCell: [String: CellRead] = [:]
        for observation in observations {
            guard let recognized = observation.topCandidates(1).first else { continue }
            let text = recognized.string
            if isBonusLabel(text) { continue }

            for range in text.characterRanges {
                let characterText = String(text[range])
                guard characterText.count == 1,
                      let letter = characterText.first,
                      PolishAlphabet.isPolishLetter(letter),
                      let box = try? recognized.boundingBox(for: range),
                      let coordinate = mapper.coordinate(for: box.boundingBox),
                      sampler.cellLooksOccupied(row: coordinate.row, column: coordinate.column) else {
                    continue
                }

                let normalized = PolishAlphabet.normalizeLetter(letter)
                let confidence = Double(recognized.confidence)
                let key = "\(coordinate.row):\(coordinate.column)"
                let candidate = CellRead(
                    row: coordinate.row,
                    column: coordinate.column,
                    letter: normalized,
                    confidence: confidence,
                    candidates: [LetterCandidate(letter: normalized, distance: 1 - confidence)]
                )

                if let existing = readsByCell[key] {
                    if candidate.confidence > existing.confidence {
                        readsByCell[key] = candidate
                    }
                } else {
                    readsByCell[key] = candidate
                }
            }
        }

        var board = Board(bonuses: bonuses)
        let cells = readsByCell.values.sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            return $0.column < $1.column
        }

        for cell in cells {
            if let letter = cell.letter {
                board = board.setCell(row: cell.row, column: cell.column, letter: letter, isBlank: cell.isBlank)
            }
        }

        guard !cells.isEmpty else {
            throw BoardImageReaderError.textRecognitionFailed
        }

        return BoardReadResult(board: board, cells: cells)
    }

    private func recognizeText(in imageURL: URL) throws -> [VNRecognizedTextObservation] {
        let accurateRequest = makeTextRequest(recognitionLevel: .accurate)
        let fastRequest = makeTextRequest(recognitionLevel: .fast)
        let handler = VNImageRequestHandler(url: imageURL)
        try handler.perform([accurateRequest, fastRequest])
        return (accurateRequest.results ?? []) + (fastRequest.results ?? [])
    }

    private func makeTextRequest(recognitionLevel: VNRequestTextRecognitionLevel) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["pl-PL", "en-US"]
        request.customWords = PolishAlphabet.letters.map(String.init)
        request.minimumTextHeight = 0.005
        return request
    }

    private func isBonusLabel(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.count <= 3 && normalized.contains(where: \.isNumber) {
            return true
        }
        return ["DL", "TL", "DW"].contains(normalized)
    }
}

public struct DictionaryBoardRepairer: Sendable {
    private let dictionary: WordDictionary

    public init(dictionary: WordDictionary) {
        self.dictionary = dictionary
    }

    public func invalidWords(on board: Board) -> [BoardWord] {
        BoardWordExtractor.extractWords(from: board).filter { !dictionary.contains($0.text) }
    }
}

private struct BoardImageMapper {
    let width: Int
    let height: Int
    let boardX: Double
    let boardY: Double
    let boardSize: Double

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.boardSize = Double(min(width, height))
        self.boardX = (Double(width) - boardSize) / 2
        self.boardY = (Double(height) - boardSize) / 2
    }

    func coordinate(for normalizedBoundingBox: CGRect) -> (row: Int, column: Int)? {
        let x = Double(normalizedBoundingBox.midX) * Double(width)
        let y = (1 - Double(normalizedBoundingBox.midY)) * Double(height)
        guard x >= boardX, x < boardX + boardSize, y >= boardY, y < boardY + boardSize else {
            return nil
        }

        let cellSize = boardSize / Double(Board.size)
        let column = Int((x - boardX) / cellSize)
        let row = Int((y - boardY) / cellSize)
        guard Board.isInside(row: row, column: column) else { return nil }
        return (row, column)
    }

    func sampleRect(row: Int, column: Int) -> CGRect {
        let cellSize = boardSize / Double(Board.size)
        let inset = cellSize * 0.2
        return CGRect(
            x: boardX + Double(column) * cellSize + inset,
            y: boardY + Double(row) * cellSize + inset,
            width: cellSize - inset * 2,
            height: cellSize - inset * 2
        )
    }
}

private final class BoardColorSampler {
    private let width: Int
    private let height: Int
    private let pixels: [UInt8]
    private let bytesPerRow: Int
    private let mapper: BoardImageMapper

    init(image: CGImage, mapper: BoardImageMapper) {
        let imageWidth = image.width
        let imageHeight = image.height
        self.width = imageWidth
        self.height = imageHeight
        self.mapper = mapper

        let bytesPerPixel = 4
        let rowBytes = imageWidth * bytesPerPixel
        self.bytesPerRow = rowBytes
        var data = [UInt8](repeating: 0, count: imageHeight * rowBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { buffer in
            if let context = CGContext(
                data: buffer.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            }
        }
        self.pixels = data
    }

    func cellLooksOccupied(row: Int, column: Int) -> Bool {
        let rect = mapper.sampleRect(row: row, column: column)
        var orangePixels = 0
        var sampledPixels = 0

        let minX = max(0, Int(rect.minX))
        let maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height - 1, Int(rect.maxY))
        let step = max(1, min(maxX - minX + 1, maxY - minY + 1) / 12)

        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let offset = y * bytesPerRow + x * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                sampledPixels += 1
                if red >= 190 && green >= 120 && green <= 210 && blue <= 130 && red > blue + 70 {
                    orangePixels += 1
                }
                x += step
            }
            y += step
        }

        guard sampledPixels > 0 else { return false }
        return Double(orangePixels) / Double(sampledPixels) > 0.35
    }
}

private extension String {
    var characterRanges: [Range<String.Index>] {
        indices.map { index in
            index..<self.index(after: index)
        }
    }
}
