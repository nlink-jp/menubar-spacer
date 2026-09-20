import XCTest
@testable import MenubarSpacer

@MainActor
final class SpacingViewModelTests: XCTestCase {
    private var preferences: StubSpacingPreferences!
    private var backups: StubBackupStore!
    private func makeModel() -> SpacingViewModel {
        SpacingViewModel(coordinator: SpacingCoordinator(preferences: preferences, backups: backups,
                                                         now: { Date(timeIntervalSince1970: 0) }))
    }

    override func setUp() {
        super.setUp()
        preferences = StubSpacingPreferences()
        backups = StubBackupStore()
    }

    func testItOpensOnThePresetTheMacIsAlreadyAt() {
        preferences.currentHost = .uniform(24)
        XCTAssertEqual(makeModel().selection, .wide)
    }

    func testAStateWeDidNotProduceOpensOnTheDefaultChoice() {
        // Nothing sensible to preselect, and the app must not pretend 13 is one
        // of its presets.
        preferences.currentHost = .uniform(13)
        let model = makeModel()
        XCTAssertEqual(model.selection, .osDefault)
        XCTAssertNil(model.state.preset)
    }

    func testApplyingWritesAndReportsWhatToDoNext() {
        let model = makeModel()
        model.selection = .narrow
        model.apply()

        XCTAssertEqual(preferences.currentHost, .uniform(8))
        XCTAssertEqual(model.state.currentHost, .uniform(8), "the view must show the new state")
        XCTAssertEqual(model.message,
                       OutcomeMessage.apply(.applied(.uniform(8))))
        XCTAssertTrue(model.canUndo)
    }




    func testUndoIsOfferedOnlyWhileSomethingOfOursIsInEffect() {
        let model = makeModel()
        XCTAssertFalse(model.canUndo)

        model.selection = .wide
        model.apply()
        XCTAssertTrue(model.canUndo)

        model.restore()
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(preferences.currentHost, .unset)
    }

    func testUndoIsStillOfferedWhenTheRecordCannotBeRead() {
        // The one case where "no record" and "cannot read the record" must not
        // look the same: the Mac may well still be changed.
        backups.loadError = .unreadable("damaged")
        XCTAssertTrue(makeModel().canUndo)
    }

    func testRestoringResetsTheSelectionToWhatTheMacNowHolds() {
        let model = makeModel()
        model.selection = .wide
        model.apply()
        model.restore()
        XCTAssertEqual(model.selection, .osDefault)
    }

    func testAFailureIsReportedAsTextRatherThanThrown() {
        backups.loadError = .unreadable("damaged")
        let model = makeModel()
        model.selection = .minimum
        model.apply()

        XCTAssertEqual(model.message, OutcomeMessage.failure(BackupStoreError.unreadable("damaged")))
        XCTAssertTrue(preferences.appliedOperations.isEmpty, "a failure must not have written")
    }

    func testTheEscapeHatchWorksFromTheUIWhenTheRecordIsDamaged() {
        preferences.currentHost = .uniform(24)
        backups.loadError = .unreadable("damaged")
        let model = makeModel()
        model.selection = .osDefault
        model.apply()

        XCTAssertEqual(preferences.currentHost, .unset)
        XCTAssertEqual(model.message,
                       OutcomeMessage.apply(.applied(.unset)))
    }


    func testApplyingOverAnOutsideChangeTellsTheUserWhatItReplaced() {
        let model = makeModel()
        model.selection = .minimum
        model.apply()

        preferences.currentHost = .uniform(30)   // a hand-run `defaults write`
        model.selection = .wide
        model.apply()

        XCTAssertEqual(model.message,
                       OutcomeMessage.apply(.appliedOverExternalChange(.uniform(24),
                                                                       replaced: .uniform(30)))
                          )
    }

    // MARK: the every-host value reaches the sentences

    /// The wiring, not the wording: deleting `everyHost:` from the view model
    /// used to leave every test green.
    func testTheWindowsMessagesKnowAboutTheEveryHostValue() {
        preferences.anyHost = .uniform(6)
        let model = makeModel()
        model.selection = .osDefault
        model.apply()
        XCTAssertEqual(model.message,
                       OutcomeMessage.apply(.alreadyApplied(.unset), everyHost: .uniform(6)))
        XCTAssertNotEqual(model.message, OutcomeMessage.apply(.alreadyApplied(.unset)))

        model.selection = .minimum
        model.apply()
        model.restore()
        XCTAssertEqual(model.message,
                       OutcomeMessage.restore(.restored(.unset), everyHost: .uniform(6)))
    }

    // MARK: after a save that failed

    func testAfterAFailedSaveTheWindowOffersNothingAndShowsNoPhantom() {
        let model = makeModel()
        model.selection = .narrow
        model.apply()
        XCTAssertEqual(model.state.currentHost, .uniform(8))

        preferences.writeError = .synchronizationFailed(actual: .uniform(4))
        preferences.failureLands = true
        model.selection = .minimum
        model.apply()

        XCTAssertTrue(model.isInDoubt)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.state.currentHost, .uniform(8),
                       "the window must not display the value macOS reported and did not keep")
        XCTAssertEqual(model.message, OutcomeMessage.failure(SpacingWriteError.processInDoubt))
        XCTAssertFalse(model.message?.contains("try again") ?? true)

        preferences.writeError = nil
        let writes = preferences.appliedOperations.count
        model.apply()
        model.restore()
        XCTAssertEqual(preferences.appliedOperations.count, writes, "nothing more is written from this window")
    }
}
