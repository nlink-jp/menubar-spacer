import XCTest
@testable import MenubarSpacer

final class LaunchTests: XCTestCase {
    func testAnOrdinaryLaunchRuns() {
        XCTAssertEqual(Launch.decide(otherInstanceCount: 0), .run)
    }

    func testASecondCopyExitsInsteadOfOpeningASecondWindow() {
        XCTAssertEqual(Launch.decide(otherInstanceCount: 1), .exitAlreadyRunning)
        XCTAssertEqual(Launch.decide(otherInstanceCount: 3), .exitAlreadyRunning)
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
            OutcomeMessage.scopeNote,
        ]
    }

    /// Both limits were found by using the app, and both are things a person
    /// would otherwise discover as "it didn't work". They belong in the window,
    /// not only in the README.
    func testTheScopeNoteNamesWhatTheSettingDoesNotReach() {
        let note = OutcomeMessage.scopeNote
        XCTAssertTrue(note.contains("sign out"), note)
        XCTAssertTrue(note.contains("macOS's own icons"), note)
        XCTAssertTrue(note.contains("next launches"), note)
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
