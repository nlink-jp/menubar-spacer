import XCTest
@testable import MenubarSpacer

@MainActor
final class SpacingViewModelTests: XCTestCase {
    private var preferences: StubSpacingPreferences!
    private var backups: StubBackupStore!
    private var previewedSeconds: [Double] = []

    private func makeModel() -> SpacingViewModel {
        SpacingViewModel(
            coordinator: SpacingCoordinator(preferences: preferences, backups: backups,
                                            now: { Date(timeIntervalSince1970: 0) }),
            startPreview: { self.previewedSeconds.append($0) }
        )
    }

    override func setUp() {
        super.setUp()
        preferences = StubSpacingPreferences()
        backups = StubBackupStore()
        previewedSeconds = []
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
                       OutcomeMessage.apply(.applied(.uniform(8))) + " " + OutcomeMessage.previewNote)
        XCTAssertTrue(model.canUndo)
    }

    /// The change is invisible in every app that is already running, so a
    /// successful apply has to show its own result.
    func testASuccessfulApplyShowsTheResultItself() {
        let model = makeModel()
        model.selection = .wide
        model.apply()
        XCTAssertEqual(previewedSeconds, [Launch.defaultPreviewSeconds])
    }

    func testAnApplyThatChangedNothingDoesNotPutIconsUp() {
        let model = makeModel()
        model.selection = .osDefault      // the Mac is already at the default
        model.apply()

        XCTAssertEqual(previewedSeconds, [], "nothing changed, so there is nothing to show")
        XCTAssertEqual(model.message, OutcomeMessage.apply(.alreadyApplied(.unset)))
    }

    func testAnIgnoredWriteDoesNotClaimToShowTheResult() {
        preferences.readBackOverride = .unset
        let model = makeModel()
        model.selection = .wide
        model.apply()

        XCTAssertEqual(previewedSeconds, [])
        XCTAssertEqual(model.message, OutcomeMessage.apply(.noEffect(expected: .uniform(24),
                                                                     actual: .unset)))
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
                       OutcomeMessage.apply(.applied(.unset)) + " " + OutcomeMessage.previewNote)
    }

    func testShowingTheCurrentSpacingStartsAChildAndChangesNothing() {
        let model = makeModel()
        model.showCurrentSpacing()

        XCTAssertEqual(previewedSeconds, [Launch.defaultPreviewSeconds])
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
        XCTAssertEqual(backups.saveCount, 0)
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
                           + " " + OutcomeMessage.previewNote)
    }
}
