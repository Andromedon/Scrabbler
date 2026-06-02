import Foundation

public enum StatusTextFormatter {
    public static func durationSeconds(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int((seconds * 1_000).rounded())) ms"
        }

        return String(format: "%.1f s", seconds)
    }

    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    public static func solveTimingText(
        solverWasLive: Bool,
        solverLoadSeconds: TimeInterval,
        solveSeconds: TimeInterval,
        totalSeconds: TimeInterval
    ) -> String {
        let source = solverWasLive ? "solver in memory" : "solver loaded from cache"
        return "\(source) · prepare \(durationSeconds(solverLoadSeconds)) · solve \(durationSeconds(solveSeconds)) · total \(durationSeconds(totalSeconds))"
    }

    public static func boardReadTimingText(
        importSeconds: TimeInterval,
        ocrSeconds: TimeInterval,
        validationSeconds: TimeInterval,
        totalSeconds: TimeInterval
    ) -> String {
        "photo \(durationSeconds(importSeconds)) · OCR \(durationSeconds(ocrSeconds)) · validation \(durationSeconds(validationSeconds)) · total \(durationSeconds(totalSeconds))"
    }

    public static func boardValidationWaitingText(
        isDictionaryLoading: Bool,
        hasSolverLoadTask: Bool,
        isDictionaryCacheAvailable: Bool
    ) -> String {
        if isDictionaryLoading || hasSolverLoadTask {
            return "Loading dictionary for board validation..."
        }
        if isDictionaryCacheAvailable {
            return "Board validation will run from cached dictionary."
        }
        return "Load Dictionary to validate board words."
    }

    public static func dictionaryTimingText(loadSeconds: TimeInterval) -> String {
        "dictionary \(durationSeconds(loadSeconds))"
    }

    public static func dictionaryButtonTitle(isReady: Bool, isCacheAvailable: Bool) -> String {
        if isReady {
            return "Dictionary Loaded"
        }
        if isCacheAvailable {
            return "Dictionary Cached"
        }
        return "Load Dictionary"
    }

    public static func dictionaryLoadStatusText(sourceKind: DictionarySourceKind, usedCache: Bool) -> String {
        switch (sourceKind, usedCache) {
        case (.full, true):
            return "Full dictionary loaded from cache"
        case (.full, false):
            return "Full dictionary loaded and cached"
        case (.sample, _):
            return "Sample dictionary loaded"
        }
    }
}
