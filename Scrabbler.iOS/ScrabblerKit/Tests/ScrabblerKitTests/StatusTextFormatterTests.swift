import Foundation
import Testing
@testable import ScrabblerKit

@Suite("Status text formatter")
struct StatusTextFormatterTests {
    @Test func durationUsesMillisecondsBelowOneSecond() {
        #expect(StatusTextFormatter.durationSeconds(0.124) == "124 ms")
        #expect(StatusTextFormatter.durationSeconds(0.9994) == "999 ms")
    }

    @Test func durationUsesSecondsAtOneSecondAndAbove() {
        #expect(StatusTextFormatter.durationSeconds(1.0) == "1.0 s")
        #expect(StatusTextFormatter.durationSeconds(12.34) == "12.3 s")
    }

    @Test func solveTimingDescribesSourceAndDurations() {
        #expect(
            StatusTextFormatter.solveTimingText(
                solverWasLive: true,
                solverLoadSeconds: 0.0,
                solveSeconds: 2.34,
                totalSeconds: 2.35
            ) == "solver in memory · prepare 0 ms · solve 2.3 s · total 2.4 s"
        )

        #expect(
            StatusTextFormatter.solveTimingText(
                solverWasLive: false,
                solverLoadSeconds: 0.43,
                solveSeconds: 1.0,
                totalSeconds: 1.43
            ) == "solver loaded from cache · prepare 430 ms · solve 1.0 s · total 1.4 s"
        )
    }

    @Test func boardReadTimingIncludesEveryStage() {
        #expect(
            StatusTextFormatter.boardReadTimingText(
                importSeconds: 0.1,
                ocrSeconds: 1.23,
                validationSeconds: 0.04,
                totalSeconds: 1.37
            ) == "photo 100 ms · OCR 1.2 s · validation 40 ms · total 1.4 s"
        )
    }

    @Test func boardValidationWaitingTextPrioritizesActiveLoadThenCache() {
        #expect(
            StatusTextFormatter.boardValidationWaitingText(
                isDictionaryLoading: true,
                hasSolverLoadTask: false,
                isDictionaryCacheAvailable: true
            ) == "Loading dictionary for board validation..."
        )
        #expect(
            StatusTextFormatter.boardValidationWaitingText(
                isDictionaryLoading: false,
                hasSolverLoadTask: true,
                isDictionaryCacheAvailable: false
            ) == "Loading dictionary for board validation..."
        )
        #expect(
            StatusTextFormatter.boardValidationWaitingText(
                isDictionaryLoading: false,
                hasSolverLoadTask: false,
                isDictionaryCacheAvailable: true
            ) == "Board validation will run from cached dictionary."
        )
        #expect(
            StatusTextFormatter.boardValidationWaitingText(
                isDictionaryLoading: false,
                hasSolverLoadTask: false,
                isDictionaryCacheAvailable: false
            ) == "Load Dictionary to validate board words."
        )
    }

    @Test func percentRoundsToWholePercent() {
        #expect(StatusTextFormatter.percent(0.734) == "73%")
        #expect(StatusTextFormatter.percent(0.735) == "74%")
    }

    @Test func dictionaryButtonTitleReflectsReadinessAndCache() {
        #expect(StatusTextFormatter.dictionaryButtonTitle(isReady: true, isCacheAvailable: true) == "Dictionary Loaded")
        #expect(StatusTextFormatter.dictionaryButtonTitle(isReady: false, isCacheAvailable: true) == "Dictionary Cached")
        #expect(StatusTextFormatter.dictionaryButtonTitle(isReady: false, isCacheAvailable: false) == "Load Dictionary")
    }

    @Test func dictionaryLoadStatusTextDescribesSourceAndCache() {
        #expect(StatusTextFormatter.dictionaryLoadStatusText(sourceKind: .full, usedCache: true) == "Full dictionary loaded from cache")
        #expect(StatusTextFormatter.dictionaryLoadStatusText(sourceKind: .full, usedCache: false) == "Full dictionary loaded and cached")
        #expect(StatusTextFormatter.dictionaryLoadStatusText(sourceKind: .sample, usedCache: false) == "Sample dictionary loaded")
        #expect(StatusTextFormatter.dictionaryLoadStatusText(sourceKind: .sample, usedCache: true) == "Sample dictionary loaded")
    }
}
