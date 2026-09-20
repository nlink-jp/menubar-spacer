import XCTest
@testable import MenubarSpacer

/// These never touch the real preference domain: the coordinator's collaborators
/// are the in-memory stubs, by construction.
final class SpacingCoordinatorTests: XCTestCase {
    private var preferences: StubSpacingPreferences!
    private var backups: StubBackupStore!
    private var coordinator: SpacingCoordinator!
    private let fixedDate = Date(timeIntervalSince1970: 1_000)

    override func setUp() {
        super.setUp()
        preferences = StubSpacingPreferences()
        backups = StubBackupStore()
        preferences.journal = backups            // one shared ordering journal
        coordinator = SpacingCoordinator(preferences: preferences, backups: backups,
                                         now: { self.fixedDate })
    }

    // MARK: apply

    func testApplyingAPresetWritesBothKeysAndRecordsTheWayBack() throws {
        XCTAssertEqual(try coordinator.apply(.minimum), .applied(.uniform(4)))
        XCTAssertEqual(preferences.currentHost, .uniform(4))
        XCTAssertEqual(backups.record?.original, .unset)
        XCTAssertEqual(backups.record?.applied, .uniform(4))
        XCTAssertEqual(backups.record?.capturedAt, fixedDate)
    }

    /// The ordering itself, not a side effect of it: the record must be stored
    /// before the write and corrected after it, all inside one lock.
    func testTheRecordIsStoredBeforeTheWriteAndCorrectedAfterIt() throws {
        _ = try coordinator.apply(.wide)
        XCTAssertEqual(backups.journal, ["lock", "load", "save", "write", "save", "unlock"])
    }

    func testEveryMutatingPathRunsUnderTheLock() throws {
        _ = try coordinator.apply(.wide)
        _ = try coordinator.restore()
        for (index, entry) in backups.journal.enumerated() where entry == "write" {
            let opened = backups.journal[..<index].filter { $0 == "lock" }.count
            let closed = backups.journal[..<index].filter { $0 == "unlock" }.count
            XCTAssertGreaterThan(opened, closed, "a write happened outside the lock")
        }
    }

    func testTheBackupIsStoredBeforeTheFirstWrite() throws {
        preferences.writeError = .synchronizationFailed(actual: .unset)
        XCTAssertThrowsError(try coordinator.apply(.wide))
        XCTAssertEqual(backups.record?.original, .unset)
        XCTAssertEqual(backups.journal.firstIndex(of: "save"),
                       backups.journal.firstIndex(of: "write").map { $0 - 1 })
    }

    func testTheOriginalSurvivesASecondApply() throws {
        preferences.currentHost = .uniform(12)  // a value the user had set by hand
        _ = try coordinator.apply(.minimum)
        _ = try coordinator.apply(.wide)

        XCTAssertEqual(preferences.currentHost, .uniform(24))
        XCTAssertEqual(backups.record?.original, .uniform(12))
        XCTAssertEqual(backups.record?.applied, .uniform(24))
    }

    /// A pre-app value far outside anything this app would produce still has to
    /// come back. This is the case that used to be recorded and then rejected.
    func testAnUnusualPreexistingValueIsRecordedAndRestored() throws {
        preferences.currentHost = .uniform(100)

        XCTAssertEqual(try coordinator.apply(.minimum), .applied(.uniform(4)))
        XCTAssertEqual(backups.record?.original, .uniform(100))
        XCTAssertEqual(try coordinator.restore(), .restored(.uniform(100)))
        XCTAssertEqual(preferences.currentHost, .uniform(100))
    }

    func testApplyingTheSameValueTwiceWritesNothingTheSecondTime() throws {
        _ = try coordinator.apply(.narrow)
        XCTAssertEqual(try coordinator.apply(.narrow), .alreadyApplied(.uniform(8)))
        XCTAssertEqual(preferences.appliedOperations.count, 1)
    }

    func testOnlyTheDifferingKeyIsWritten() throws {
        preferences.currentHost = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        _ = try coordinator.apply(.minimum)
        XCTAssertEqual(preferences.appliedOperations,
                       [[.set(key: .selectionPadding, value: .integer(4))]])
    }

    func testReturningToTheOriginalDropsTheBackup() throws {
        _ = try coordinator.apply(.wide)
        XCTAssertEqual(try coordinator.apply(.osDefault), .applied(.unset))
        XCTAssertNil(backups.record)
    }

    // MARK: apply — the write did not fully land

    func testAnIgnoredWriteIsReportedRatherThanCalledSuccess() throws {
        preferences.readBackOverride = .unset
        XCTAssertEqual(try coordinator.apply(.wide), .noEffect(expected: .uniform(24), actual: .unset))
    }

    /// After a half-landed write the record must describe the Mac, not the
    /// target — otherwise the next restore accuses an outsider of our own mess.
    func testAHalfLandedWriteLeavesARecordThatMatchesTheMac() throws {
        preferences.currentHost = .uniform(12)
        let half = SpacingSettings(spacing: .integer(24), selectionPadding: .integer(12))
        preferences.readBackOverride = half

        XCTAssertEqual(try coordinator.apply(.wide), .noEffect(expected: .uniform(24), actual: half))
        XCTAssertEqual(backups.record?.original, .uniform(12))
        XCTAssertEqual(backups.record?.applied, half)

        preferences.readBackOverride = nil
        XCTAssertEqual(try coordinator.restore(), .restored(.uniform(12)))
    }

    func testAHalfLandedRestoreCanBeRetried() throws {
        _ = try coordinator.apply(.wide)
        let half = SpacingSettings(spacing: .absent, selectionPadding: .integer(24))
        preferences.readBackOverride = half

        XCTAssertEqual(try coordinator.restore(), .noEffect(expected: .unset, actual: half))

        preferences.readBackOverride = nil
        XCTAssertEqual(try coordinator.restore(), .restored(.unset))
        XCTAssertNil(backups.record)
    }

    // MARK: apply — someone else changed the keys

    func testApplyingOverAnExternalChangeSaysSo() throws {
        _ = try coordinator.apply(.minimum)
        preferences.currentHost = .uniform(30)   // a hand-run `defaults write`

        XCTAssertEqual(try coordinator.apply(.wide),
                       .appliedOverExternalChange(.uniform(24), replaced: .uniform(30)))
        // The way back is still the state from before this app ever ran.
        XCTAssertEqual(backups.record?.original, .unset)
    }

    // MARK: apply — the record cannot be read

    func testAnUnreadableBackupBlocksAValuePreset() {
        backups.loadError = .unreadable("damaged")
        XCTAssertThrowsError(try coordinator.apply(.minimum)) { error in
            XCTAssertEqual(error as? BackupStoreError, .unreadable("damaged"))
        }
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
        XCTAssertEqual(backups.saveCount, 0)
        XCTAssertEqual(backups.quarantineCount, 0)
    }

    func testReturningToTheOSDefaultStaysAvailableWithAnUnreadableBackup() throws {
        preferences.currentHost = .uniform(24)
        backups.loadError = .unreadable("damaged")

        XCTAssertEqual(try coordinator.apply(.osDefault), .applied(.unset))
        XCTAssertEqual(preferences.currentHost, .unset)
        // Moved aside, not deleted: it may still be readable by a person.
        XCTAssertEqual(backups.quarantineCount, 1)
        XCTAssertEqual(backups.clearCount, 0)
    }

    /// The way home was taken and the Mac did not go there: this app's value is
    /// still in effect, and a file that merely could not be read may be the way
    /// back from it. v0.1.0 set it aside regardless.
    func testAnUnreadableBackupStaysWhenTheWayHomeDidNotTake() throws {
        preferences.currentHost = .uniform(24)
        backups.loadError = .unreadable("transient I/O error")

        preferences.readBackOverride = .uniform(24)                       // ignored outright
        XCTAssertEqual(try coordinator.apply(.osDefault), .noEffect(expected: .unset, actual: .uniform(24)))
        XCTAssertEqual(backups.quarantineCount, 0)

        let half = SpacingSettings(spacing: .absent, selectionPadding: .integer(24))
        preferences.readBackOverride = half                                // one key only
        XCTAssertEqual(try coordinator.apply(.osDefault), .noEffect(expected: .unset, actual: half))
        XCTAssertEqual(backups.quarantineCount, 0)
        XCTAssertEqual(backups.clearCount, 0)
    }

    /// A file that does not decode is no way back whatever the write did.
    func testAnUndecodableBackupIsSetAsideEvenWhenTheWayHomeDidNotTake() throws {
        preferences.currentHost = .uniform(24)
        backups.loadError = .undecodable("not JSON")
        preferences.readBackOverride = .uniform(24)

        XCTAssertEqual(try coordinator.apply(.osDefault), .noEffect(expected: .unset, actual: .uniform(24)))
        XCTAssertEqual(backups.quarantineCount, 1)
    }

    /// A damaged record must survive an action that wrote nothing — including a
    /// read failure that was only transient.
    func testAnUnreadableBackupIsUntouchedWhenNothingIsWritten() throws {
        backups.loadError = .unreadable("transient I/O error")

        XCTAssertEqual(try coordinator.apply(.osDefault), .alreadyApplied(.unset))
        XCTAssertEqual(backups.quarantineCount, 0)
        XCTAssertEqual(backups.clearCount, 0)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
    }

    /// The read succeeded and the bytes are not a record: no later read will do
    /// better. Left in place the file refuses every value preset for good, and
    /// here no write follows to move it aside — so the way home does, even
    /// though it writes nothing. (A file that merely could not be read is the
    /// test above, and is still left alone.)
    func testARecordNoRetryCanReadIsSetAsideOnTheWayHome() throws {
        backups.loadError = .undecodable("not JSON")

        let outcome = try coordinator.apply(.osDefault)
        XCTAssertEqual(outcome, .alreadyAppliedRecordSetAside(.unset))
        XCTAssertFalse(OutcomeMessage.apply(outcome).contains("Nothing was changed"),
                       "a file was moved: the sentence must not say nothing changed")
        XCTAssertEqual(backups.quarantineCount, 1)
        XCTAssertEqual(backups.clearCount, 0, "moved aside, never deleted")
        XCTAssertTrue(preferences.appliedOperations.isEmpty)

        // The dead end this closes: value presets work again, with a way back.
        XCTAssertEqual(try coordinator.apply(.minimum), .applied(.uniform(4)))
        XCTAssertEqual(try coordinator.restore(), .restored(.unset))
    }

    func testAnUndecodableBackupStillBlocksAValuePreset() {
        backups.loadError = .undecodable("not JSON")
        XCTAssertThrowsError(try coordinator.apply(.minimum))
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
        XCTAssertEqual(backups.quarantineCount, 0)
    }

    // MARK: a write that fails, or changes nothing

    /// When macOS REPORTS that a change was not saved. (A save that fails without
    /// a report is invisible at write time — ADR-0001 §2, known limit — and no
    /// test here pretends otherwise: the stub's reads are truthful.)
    func testAfterAReportedFailureTheRecordIsAsItWasAndUndoStillWorks() throws {
        XCTAssertEqual(try coordinator.apply(.narrow), .applied(.uniform(8)))
        let before = backups.record

        preferences.writeError = .synchronizationFailed(actual: .uniform(8))
        XCTAssertThrowsError(try coordinator.apply(.minimum))
        XCTAssertEqual(backups.record, before)

        preferences.writeError = nil
        XCTAssertEqual(try coordinator.restore(), .restored(.unset))
        XCTAssertNil(backups.record)
    }

    /// With no earlier record the new one stays: right if the write landed after
    /// all, harmless if it did not.
    func testAFirstChangeThatFailsLeavesARecordThatUndoClearsHarmlessly() throws {
        preferences.currentHost = .uniform(12)
        preferences.writeError = .synchronizationFailed(actual: .uniform(12))
        XCTAssertThrowsError(try coordinator.apply(.minimum))
        XCTAssertEqual(backups.record?.original, .uniform(12))

        preferences.writeError = nil
        XCTAssertEqual(try coordinator.restore(), .alreadyOriginal)
        XCTAssertNil(backups.record)
        XCTAssertEqual(preferences.currentHost, .uniform(12))
    }

    func testAnUndoThatFailsKeepsTheWayBack() throws {
        preferences.currentHost = .uniform(12)
        XCTAssertEqual(try coordinator.apply(.wide), .applied(SpacingPreset.wide.settings))
        let before = backups.record

        preferences.writeError = .synchronizationFailed(actual: SpacingPreset.wide.settings)
        XCTAssertThrowsError(try coordinator.restore())
        XCTAssertEqual(backups.record, before)

        preferences.writeError = nil
        XCTAssertEqual(try coordinator.restore(), .restored(.uniform(12)))
    }

    /// Nothing changed, so the record is as it was — and a value someone else
    /// set is not adopted as this app's own, which Undo would then remove.
    func testAChangeThatDoesNothingOverAnOutsideValueDoesNotAdoptIt() throws {
        XCTAssertEqual(try coordinator.apply(.minimum), .applied(.uniform(4)))
        let before = backups.record
        preferences.currentHost = .uniform(30)          // someone else

        preferences.readBackOverride = .uniform(30)     // the OS ignores the write
        XCTAssertEqual(try coordinator.apply(.wide),
                       .noEffect(expected: SpacingPreset.wide.settings, actual: .uniform(30)))
        XCTAssertEqual(backups.record, before)

        preferences.readBackOverride = nil
        preferences.writeError = .synchronizationFailed(actual: .uniform(30))
        XCTAssertThrowsError(try coordinator.apply(.wide))
        XCTAssertEqual(backups.record, before)

        preferences.writeError = nil
        XCTAssertEqual(try coordinator.restore(),
                       .refusedExternalChange(current: .uniform(30), original: .unset))
        XCTAssertEqual(preferences.currentHost, .uniform(30))
    }

    // MARK: what is in effect

    func testWhatIsInEffectFallsBackToTheEveryHostValue() {
        preferences.anyHost = .uniform(6)
        let state = coordinator.state()
        XCTAssertEqual(state.currentHost, .unset)
        XCTAssertEqual(state.effective, .uniform(6))
        XCTAssertTrue(state.inheritsFromEveryHost)
        XCTAssertNotNil(SpacingDescription.everyHostNote(state))
    }

    func testThisHostsValueWinsOverTheEveryHostValue() throws {
        preferences.anyHost = .uniform(6)
        _ = try coordinator.apply(.minimum)
        let state = coordinator.state()
        XCTAssertEqual(state.effective, .uniform(4))
        XCTAssertFalse(state.inheritsFromEveryHost)
    }

    /// The overlay is per key: the two keys are independent preferences, and the
    /// OS resolves each on its own.
    func testTheOverlayIsPerKey() {
        preferences.currentHost = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        preferences.anyHost = SpacingSettings(spacing: .integer(9), selectionPadding: .integer(6))
        let state = coordinator.state()
        XCTAssertEqual(state.effective,
                       SpacingSettings(spacing: .integer(4), selectionPadding: .integer(6)))
        XCTAssertTrue(state.inheritsFromEveryHost)
    }

    /// While this Mac's own setting hides the every-host one, the note is still
    /// there: that is when "macOS default" is about to mean something else.
    func testTheEveryHostValueIsMentionedEvenWhileItIsOverridden() throws {
        preferences.anyHost = .uniform(6)
        _ = try coordinator.apply(.minimum)
        let note = try XCTUnwrap(SpacingDescription.everyHostNote(coordinator.state()))
        XCTAssertTrue(note.hasPrefix("A spacing of 6 is also set for every Mac"), note)
        XCTAssertTrue(note.contains("not to Apple's"), note)
    }

    /// The sentences must not contradict the header: with an every-host value,
    /// clearing this Mac's setting does not produce "the macOS default".
    func testOutcomesSayWhatAppliesWhenThisMacsSettingIsCleared() throws {
        let six = SpacingSettings.uniform(6)
        let cleared: [String] = [
            OutcomeMessage.apply(.applied(.unset), everyHost: six),
            OutcomeMessage.apply(.alreadyApplied(.unset), everyHost: six),
            OutcomeMessage.apply(.alreadyAppliedRecordSetAside(.unset), everyHost: six),
            OutcomeMessage.apply(.noEffect(expected: .uniform(4), actual: .unset), everyHost: six),
            OutcomeMessage.restore(.restored(.unset), everyHost: six),
            OutcomeMessage.restore(.noEffect(expected: .uniform(4), actual: .unset), everyHost: six),
        ]
        for sentence in cleared {
            XCTAssertTrue(sentence.contains("applies (6)"), sentence)
            // The first attempt appended a sentence and kept the old one, which
            // produced "Already the macOS default. … applies: 6."
            XCTAssertFalse(sentence.contains("macOS default"), sentence)
        }

        // Unchanged when the outcome leaves a setting of its own, or when there
        // is no every-host value.
        XCTAssertFalse(OutcomeMessage.apply(.applied(.uniform(4)), everyHost: six).contains("every Mac"))
        XCTAssertEqual(OutcomeMessage.apply(.applied(.unset)),
                       "Spacing is back to the macOS default. \(OutcomeMessage.relaunchNote)")
        XCTAssertEqual(OutcomeMessage.apply(.alreadyApplied(.unset)),
                       "Already the macOS default. Nothing was changed.")

        // The sentences a review read aloud and found garbled.
        // A write that took for one key only: nothing is "still" anything, and
        // half of what is there is this app's — it used to say "the spacing is
        // still a setting made outside this app".
        let oneKeyOnly = SpacingSettings(spacing: .integer(8), selectionPadding: .absent)
        XCTAssertEqual(OutcomeMessage.apply(.noEffect(expected: .uniform(8), actual: oneKeyOnly)),
                       "macOS did not accept the change — only part of it took effect. "
                       + "This version of macOS may ignore the setting.")
        XCTAssertEqual(OutcomeMessage.apply(.noEffect(expected: .uniform(8), actual: .uniform(4))),
                       "macOS did not accept the change — the spacing is still 4. "
                       + "This version of macOS may ignore the setting.")
        XCTAssertEqual(OutcomeMessage.apply(.noEffect(expected: .uniform(4), actual: .unset), everyHost: six),
                       "macOS did not accept the change — this Mac still has no spacing of its own, "
                       + "so the one set for every Mac outside this app applies (6). "
                       + "This version of macOS may ignore the setting.")
        XCTAssertEqual(OutcomeMessage.apply(.appliedOverExternalChange(.uniform(8), replaced: .unset), everyHost: six),
                       "Spacing set to 8, after this Mac's own setting had been cleared outside this app. "
                       + OutcomeMessage.relaunchNote)
        // Reachable only when the saved original is not the default — so there IS
        // something to put back, and the sentence has to say what and how.
        let refusal = OutcomeMessage.restore(.refusedExternalChange(current: .unset, original: .uniform(12)))
        XCTAssertFalse(refusal.contains("Choose the macOS default"), "that is the state the Mac is already in")
        XCTAssertTrue(refusal.contains("(12) is still saved"), refusal)
        XCTAssertTrue(refusal.contains("then press Undo"), refusal)
        XCTAssertEqual(OutcomeMessage.apply(.appliedOverExternalChange(.uniform(8),
                           replaced: SpacingSettings(spacing: .integer(4), selectionPadding: .absent))),
                       "Spacing set to 8, replacing a setting that was made outside this app. "
                       + OutcomeMessage.relaunchNote)

        // Half cleared: one key this Mac's own, the other inherited.
        let half = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        XCTAssertTrue(OutcomeMessage.apply(.applied(half), everyHost: six).contains("in part from"))
    }

    func testNothingIsSaidWhenNoEveryHostValueExists() {
        let state = coordinator.state()
        XCTAssertEqual(state.effective, .unset)
        XCTAssertNil(SpacingDescription.everyHostNote(state))
    }

    // MARK: restore

    func testRestoringDeletesKeysThatWereOriginallyAbsent() throws {
        _ = try coordinator.apply(.wide)
        XCTAssertEqual(try coordinator.restore(), .restored(.unset))
        XCTAssertEqual(preferences.currentHost, .unset)
        XCTAssertNil(backups.record)
    }

    func testRestoringWithoutABackupWritesNothing() throws {
        XCTAssertEqual(try coordinator.restore(), .nothingToRestore)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
    }

    func testAnExternalChangeIsRefusedNotOverwritten() throws {
        _ = try coordinator.apply(.minimum)
        preferences.currentHost = .uniform(20)

        XCTAssertEqual(try coordinator.restore(),
                       .refusedExternalChange(current: .uniform(20), original: .unset))
        XCTAssertEqual(preferences.currentHost, .uniform(20))
        XCTAssertEqual(preferences.appliedOperations.count, 1)
        XCTAssertNotNil(backups.record)
    }

    func testAnUnreadableBackupNeverProducesARestoreWrite() throws {
        backups.loadError = .unreadable("damaged")
        XCTAssertEqual(try coordinator.restore(), .unusableBackup)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
    }

    func testRestoringWhenAlreadyOriginalClearsTheStaleRecord() throws {
        backups.record = BackupRecord(original: .unset, applied: .uniform(4), capturedAt: fixedDate)
        XCTAssertEqual(try coordinator.restore(), .alreadyOriginal)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
        XCTAssertNil(backups.record)
    }

    // MARK: failures that must not be reported as write failures

    func testACompletedWriteIsNotReportedAsAFailureBecauseCleanupFailed() throws {
        _ = try coordinator.apply(.wide)
        backups.clearError = .unreadable("cannot delete")

        // The Mac does get back to its original state; a stubborn bookkeeping
        // file must not turn that into a thrown error.
        XCTAssertEqual(try coordinator.apply(.osDefault), .applied(.unset))
        XCTAssertEqual(preferences.currentHost, .unset)
    }

    // MARK: two instances

    /// The race the lock exists for: another instance restores and clears the
    /// record while this one is mid-apply. Under the lock, this instance sees a
    /// consistent view and never records a state the app itself produced.
    func testTheLiveStateIsReadInsideTheLockNotBeforeIt() throws {
        _ = try coordinator.apply(.minimum)              // Mac 4/4, record original: unset
        backups.onLock = {
            // Another instance finishes its restore in this window.
            self.preferences.currentHost = .unset
            self.backups.record = nil
        }

        _ = try coordinator.apply(.wide)

        // `original` must be the state after the other instance's restore, not
        // the 4/4 this app had produced earlier.
        XCTAssertEqual(backups.record?.original, .unset)
        XCTAssertEqual(try coordinator.restore(), .restored(.unset))
    }

    // MARK: state

    func testStateNamesThePresetAndTheBackup() throws {
        preferences.anyHost = .uniform(6)
        _ = try coordinator.apply(.wide)

        let state = coordinator.state()
        XCTAssertEqual(state.currentHost, .uniform(24))
        XCTAssertEqual(state.anyHost, .uniform(6))
        XCTAssertEqual(state.preset, .wide)
        XCTAssertEqual(state.backup, .present)
    }

    func testStateReportsAValueWeDidNotProduce() {
        preferences.currentHost = .uniform(13)
        let state = coordinator.state()
        XCTAssertNil(state.preset)
        XCTAssertEqual(state.backup, .absent)
    }

    /// The case the throwing `load()` exists for: a UI must never be able to
    /// read this as "nothing of ours is in effect".
    func testStateDistinguishesNoBackupFromAnUnreadableOne() {
        backups.loadError = .unreadable("damaged")
        XCTAssertEqual(coordinator.state().backup, .unreadable)
        XCTAssertNotEqual(coordinator.state().backup, .absent)
    }
}

final class FileBackupStoreTests: XCTestCase {
    private var directory: URL!
    private var store: FileBackupStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("menubar-spacer-tests-" + UUID().uuidString, isDirectory: true)
        store = FileBackupStore(url: directory.appendingPathComponent("backup.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testNoFileMeansNoBackup() throws {
        XCTAssertNil(try store.load())
    }

    func testARecordRoundTripsThroughDisk() throws {
        let record = BackupRecord(original: SpacingSettings(spacing: .integer(6), selectionPadding: .absent),
                                  applied: .uniform(24),
                                  capturedAt: Date(timeIntervalSince1970: 42))
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testAnUninterpretableValueSurvivesTheRoundTrip() throws {
        let opaque = try XCTUnwrap(OpaqueValue(capturing: "8", summary: "text \"8\""))
        let record = BackupRecord(original: SpacingSettings(spacing: .other(opaque), selectionPadding: .absent),
                                  applied: .uniform(4), capturedAt: Date(timeIntervalSince1970: 1))
        try store.save(record)
        XCTAssertEqual((try store.load())?.original.spacing, .other(opaque))
    }

    func testClearingRemovesTheRecordAndIsIdempotent() throws {
        try store.save(BackupRecord(original: .unset, applied: .uniform(4), capturedAt: Date()))
        try store.clear()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.clear())
    }

    func testDamagedContentThrowsRatherThanReadingAsNoBackup() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) { error in
            guard case .undecodable = error as? BackupStoreError else {
                return XCTFail("expected .undecodable, got \(error)")
            }
        }
    }

    func testQuarantineKeepsTheBytesUnderANewName() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"original\": broken".utf8).write(to: store.url)

        try store.quarantine()

        XCTAssertNil(try store.load(), "the damaged file must no longer be the live record")
        let salvaged = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("damaged") }
        XCTAssertEqual(salvaged.count, 1)
        let content = try String(contentsOf: directory.appendingPathComponent(salvaged[0]), encoding: .utf8)
        XCTAssertTrue(content.contains("original"), "the bytes a person could still read must survive")
    }

    func testTwoQuarantinesInOneSecondKeepBothFiles() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for _ in 0..<3 {
            try Data("not a record".utf8).write(to: store.url)
            XCTAssertNoThrow(try store.quarantine())
        }
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".damaged-") }
        XCTAssertEqual(kept.count, 3, "\(kept)")
    }

    func testExclusiveAccessSerialisesTwoConcurrentHolders() throws {
        let other = FileBackupStore(url: store.url)
        let started = expectation(description: "second holder started")
        var overlapped = false
        var inside = false

        try store.withExclusiveAccess {
            let queue = DispatchQueue(label: "second")
            queue.async {
                started.fulfill()
                try? other.withExclusiveAccess { if inside { overlapped = true } }
            }
            inside = true
            wait(for: [started], timeout: 5)
            Thread.sleep(forTimeInterval: 0.2)   // the window the other holder would use
            inside = false
        }
        XCTAssertFalse(overlapped, "two holders were inside the critical section at once")
    }

    func testTheDefaultLocationIsTheAppsOwnApplicationSupportFolder() {
        let path = FileBackupStore.applicationSupport.path
        XCTAssertTrue(path.hasSuffix("/Application Support/jp.nlink.menubar-spacer/backup.json"), path)
    }
}
