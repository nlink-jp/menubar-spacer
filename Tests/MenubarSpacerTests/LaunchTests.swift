import XCTest
@testable import MenubarSpacer

final class LaunchTests: XCTestCase {
    func testAnOrdinaryLaunchRuns() {
        XCTAssertEqual(Launch.decide(arguments: [], otherInstanceCount: 0), .run)
    }

    func testASecondCopyExitsInsteadOfOpeningASecondWindow() {
        XCTAssertEqual(Launch.decide(arguments: [], otherInstanceCount: 1), .exitAlreadyRunning)
    }

    /// The preview is always a child of the running app. Guarding it would turn
    /// the feature into a silent no-op, so the decision comes first.
    func testThePreviewIsExemptFromTheSingleInstanceGuard() {
        XCTAssertEqual(Launch.decide(arguments: ["--preview"], otherInstanceCount: 1),
                       .preview(seconds: Launch.defaultPreviewSeconds))
        XCTAssertEqual(Launch.decide(arguments: ["--preview", "3"], otherInstanceCount: 4),
                       .preview(seconds: 3))
    }

    func testThePreviewArgumentsRoundTrip() {
        let arguments = Launch.previewArguments(seconds: 2.5)
        XCTAssertEqual(Launch.decide(arguments: arguments, otherInstanceCount: 0),
                       .preview(seconds: 2.5))
    }

    func testAPreviewCanNeverHoldTheMenuBarIndefinitely() {
        XCTAssertEqual(Launch.clampPreview(9_999), 30)
        XCTAssertEqual(Launch.clampPreview(0), Launch.defaultPreviewSeconds)
        XCTAssertEqual(Launch.clampPreview(-4), Launch.defaultPreviewSeconds)
        // Not finite is not "very long": it falls back like any other bad input.
        XCTAssertEqual(Launch.clampPreview(.infinity), Launch.defaultPreviewSeconds)
        XCTAssertEqual(Launch.clampPreview(.nan), Launch.defaultPreviewSeconds)
    }

    func testAnUnparseableDurationFallsBackInsteadOfFailing() {
        XCTAssertEqual(Launch.decide(arguments: ["--preview", "soon"], otherInstanceCount: 0),
                       .preview(seconds: Launch.defaultPreviewSeconds))
    }

    func testAnUnknownArgumentStillOpensTheApp() {
        XCTAssertEqual(Launch.decide(arguments: ["-NSDocumentRevisionsDebugMode", "YES"],
                                     otherInstanceCount: 0), .run)
    }
}

/// Every sentence an operator can meet, read in one place.
final class OutcomeMessageTests: XCTestCase {
    private var allMessages: [String] {
        let settings = SpacingSettings.uniform(8)
        return [
            OutcomeMessage.apply(.applied(settings)),
            OutcomeMessage.apply(.applied(.unset)),
            OutcomeMessage.apply(.alreadyApplied(settings)),
            OutcomeMessage.apply(.appliedOverExternalChange(settings, replaced: .uniform(30))),
            OutcomeMessage.apply(.noEffect(expected: settings, actual: .unset)),
            OutcomeMessage.restore(.restored(.unset)),
            OutcomeMessage.restore(.alreadyOriginal),
            OutcomeMessage.restore(.nothingToRestore),
            OutcomeMessage.restore(.refusedExternalChange(current: .uniform(30), original: .unset)),
            OutcomeMessage.restore(.unusableBackup),
            OutcomeMessage.restore(.unrestorableOriginal(.unset)),
            OutcomeMessage.restore(.noEffect(expected: .unset, actual: settings)),
            OutcomeMessage.failure(BackupStoreError.unreadable("x")),
            OutcomeMessage.failure(BackupStoreError.lockFailed("x")),
            OutcomeMessage.failure(SpacingWriteError.synchronizationFailed(actual: .unset)),
            OutcomeMessage.failure(SpacingWriteError.unrestorableValue(.spacing)),
            OutcomeMessage.failure(CocoaError(.fileWriteNoPermission)),
        ]
    }

    func testEveryOutcomeSaysSomething() {
        for message in allMessages {
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.hasSuffix(".") || message.hasSuffix("it."), message)
        }
    }

    func testNoMessageLeaksTheAppsOwnVocabulary() {
        for message in allMessages {
            for banned in ["NSStatusItem", "absent", "CFPreferences", "currentHost",
                           "backup.json", "nil", "Optional", "Error"] {
                XCTAssertFalse(message.contains(banned), "\(banned) in: \(message)")
            }
        }
    }

    /// A change nobody can see is the app's most likely complaint. Every message
    /// that reports a change must say what to do to see it.
    func testAMessageAboutAChangeSaysHowToSeeIt() {
        XCTAssertTrue(OutcomeMessage.apply(.applied(.uniform(4))).contains(OutcomeMessage.relaunchNote))
        XCTAssertTrue(OutcomeMessage.restore(.restored(.unset)).contains(OutcomeMessage.relaunchNote))
        XCTAssertTrue(OutcomeMessage.apply(.appliedOverExternalChange(.uniform(4), replaced: .uniform(9)))
            .contains(OutcomeMessage.relaunchNote))
    }

    /// And every message about something that did not happen must say so, so a
    /// refusal is never mistaken for a success.
    func testARefusalSaysNothingWasChanged() {
        for message in [OutcomeMessage.restore(.refusedExternalChange(current: .uniform(30), original: .unset)),
                        OutcomeMessage.restore(.unusableBackup),
                        OutcomeMessage.restore(.unrestorableOriginal(.unset)),
                        OutcomeMessage.failure(BackupStoreError.unreadable("x")),
                        OutcomeMessage.failure(SpacingWriteError.unrestorableValue(.spacing))] {
            XCTAssertTrue(message.lowercased().contains("nothing was changed"), message)
        }
    }

    func testTheEscapeHatchIsOfferedWheneverTheRecordIsUnusable() {
        for message in [OutcomeMessage.restore(.unusableBackup),
                        OutcomeMessage.restore(.unrestorableOriginal(.unset)),
                        OutcomeMessage.failure(BackupStoreError.unreadable("x"))] {
            XCTAssertTrue(message.contains("macOS default"), message)
        }
    }
}
