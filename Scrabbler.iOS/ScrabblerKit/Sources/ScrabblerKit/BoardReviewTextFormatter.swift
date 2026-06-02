import Foundation

public enum BoardReviewTextFormatter {
    public static func displayLetter(_ letter: Character?) -> String {
        letter.map(String.init) ?? "."
    }

    public static func bonusText(_ bonus: BonusType) -> String? {
        switch bonus {
        case .doubleLetter:
            return "2L"
        case .tripleLetter:
            return "3L"
        case .doubleWord:
            return "2W"
        case .tripleWord:
            return "3W"
        case .none:
            return nil
        }
    }

    public static func autoRepairStatusText(_ repairs: [BoardRepair]) -> String {
        repairs
            .map { repair in
                let from = displayLetter(repair.originalLetter)
                let to = displayLetter(repair.repairedLetter)
                return "\(BoardCoordinateFormatter.coordinate(row: repair.row, column: repair.column)) \(from)→\(to)"
            }
            .joined(separator: ", ")
    }

    public static func shortRepairReason(_ reason: String) -> String {
        reason.replacingOccurrences(of: "dictionary: ", with: "")
    }

    public static func reviewReasonText(for cell: CellReview) -> String {
        switch cell.reason {
        case .scoreDigitMismatch(let detected, let expected):
            return "value \(detected), \(displayLetter(cell.letter))=\(expected)"
        case .possibleMissedTile:
            return "possible missed tile"
        case .lowConfidence:
            return "low confidence \(StatusTextFormatter.percent(cell.confidence))"
        case .closeCandidates:
            return "close candidates"
        }
    }

    public static func reviewStatusText(for cells: [CellReview], maxPreviewCount: Int = 10) -> String {
        guard !cells.isEmpty else {
            return ""
        }

        let preview = cells
            .prefix(maxPreviewCount)
            .map { cell -> String in
                let candidates = cell.candidates.prefix(3).map(String.init).joined(separator: "/")
                let coordinate = BoardCoordinateFormatter.coordinate(row: cell.row, column: cell.column)
                if candidates.isEmpty {
                    return "\(coordinate)=\(displayLetter(cell.letter))"
                }
                return "\(coordinate)=\(displayLetter(cell.letter)) (\(candidates))"
            }
            .joined(separator: ", ")
        let suffix = cells.count > maxPreviewCount ? "…" : ""
        return "Check amber cells: \(preview)\(suffix)"
    }

    public static func invalidWordsStatusText(_ words: [BoardWord], maxPreviewCount: Int = 8) -> String {
        guard !words.isEmpty else {
            return "All detected board words are in the dictionary."
        }

        let preview = words
            .prefix(maxPreviewCount)
            .map { word in
                "\(word.text) \(BoardCoordinateFormatter.coordinate(row: word.coordinates[0].row, column: word.coordinates[0].column))"
            }
            .joined(separator: ", ")
        let suffix = words.count > maxPreviewCount ? "…" : ""
        return "Check words: \(preview)\(suffix)"
    }
}
