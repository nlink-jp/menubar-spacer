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
        coordinator = SpacingCoordinator(preferences: preferences, backups: backups,
                                         now: { self.fixedDate })
    }

    // MARK: apply

    func testApplyingAPresetWritesBothKeysAndRecordsTheWayBack() throws {
        let outcome = try coordinator.apply(.minimum)

        XCTAssertEqual(outcome, .applied(.uniform(4)))
        XCTAssertEqual(preferences.currentHost, .uniform(4))
        XCTAssertEqual(backups.record?.original, .unset)
        XCTAssertEqual(backups.record?.applied, .uniform(4))
        XCTAssertEqual(backups.record?.capturedAt, fixedDate)
    }

    func testTheBackupIsStoredBeforeTheFirstWrite() throws {
        // If the write fails, the way back must already be on disk.
        preferences.writeError = .synchronizationFailed
        XCTAssertThrowsError(try coordinator.apply(.wide))
        XCTAssertEqual(backups.record?.original, .unset)
        XCTAssertEqual(backups.saveCount, 1)
    }

    func testTheOriginalSurvivesASecondApply() throws {
        preferences.currentHost = .uniform(12)  // a value the user had set by hand
        _ = try coordinator.apply(.minimum)
        _ = try coordinator.apply(.wide)

        XCTAssertEqual(preferences.currentHost, .uniform(24))
        // Not 4: the record must keep the state from before this app's first write.
        XCTAssertEqual(backups.record?.original, .uniform(12))
        XCTAssertEqual(backups.record?.applied, .uniform(24))
    }

    func testApplyingTheSameValueTwiceWritesNothingTheSecondTime() throws {
        _ = try coordinator.apply(.narrow)
        let outcome = try coordinator.apply(.narrow)

        XCTAssertEqual(outcome, .alreadyApplied(.uniform(8)))
        XCTAssertEqual(preferences.appliedOperations.count, 1)
    }

    func testOnlyTheDifferingKeyIsWritten() throws {
        preferences.currentHost = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        _ = try coordinator.apply(.minimum)

        XCTAssertEqual(preferences.appliedOperations, [[.set(key: .selectionPadding, value: 4)]])
    }

    func testReturningToTheOriginalDropsTheBackup() throws {
        _ = try coordinator.apply(.wide)
        XCTAssertNotNil(backups.record)

        let outcome = try coordinator.apply(.osDefault)

        XCTAssertEqual(outcome, .applied(.unset))
        // "No backup" now means "nothing of ours is in effect".
        XCTAssertNil(backups.record)
    }

    func testAnIgnoredWriteIsReportedRatherThanCalledSuccess() throws {
        // The OS accepts the write but the scope does not hold it.
        preferences.readBackOverride = .unset
        let outcome = try coordinator.apply(.wide)

        XCTAssertEqual(outcome, .noEffect(expected: .uniform(24), actual: .unset))
        // The record stays: something may still have been written.
        XCTAssertNotNil(backups.record)
    }

    func testAnUnreadableBackupBlocksAValuePreset() {
        backups.loadError = .unreadable("damaged")
        XCTAssertThrowsError(try coordinator.apply(.minimum)) { error in
            XCTAssertEqual(error as? BackupStoreError, .unreadable("damaged"))
        }
        // Nothing was written, and the only record of the original is intact.
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
        XCTAssertEqual(backups.saveCount, 0)
        XCTAssertEqual(backups.clearCount, 0)
    }

    func testReturningToTheOSDefaultStaysAvailableWithAnUnreadableBackup() throws {
        preferences.currentHost = .uniform(24)
        backups.loadError = .unreadable("damaged")

        let outcome = try coordinator.apply(.osDefault)

        XCTAssertEqual(outcome, .applied(.unset))
        XCTAssertEqual(preferences.currentHost, .unset)
        // The unusable file is cleared once the Mac is back at the OS default.
        XCTAssertEqual(backups.clearCount, 1)
        XCTAssertEqual(backups.saveCount, 0)
    }

    // MARK: restore

    func testRestoringDeletesKeysThatWereOriginallyAbsent() throws {
        _ = try coordinator.apply(.wide)
        let outcome = try coordinator.restore()

        XCTAssertEqual(outcome, .restored(.unset))
        XCTAssertEqual(preferences.currentHost, .unset)
        XCTAssertNil(backups.record)
    }

    func testRestoringPutsBackAValueTheUserHadSet() throws {
        preferences.currentHost = .uniform(12)
        _ = try coordinator.apply(.minimum)

        XCTAssertEqual(try coordinator.restore(), .restored(.uniform(12)))
        XCTAssertEqual(preferences.currentHost, .uniform(12))
    }

    func testRestoringWithoutABackupWritesNothing() throws {
        XCTAssertEqual(try coordinator.restore(), .nothingToRestore)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
    }

    func testAnExternalChangeIsRefusedNotOverwritten() throws {
        _ = try coordinator.apply(.minimum)
        preferences.currentHost = .uniform(20)  // changed by something else

        let outcome = try coordinator.restore()

        XCTAssertEqual(outcome, .refusedExternalChange(current: .uniform(20), original: .unset))
        XCTAssertEqual(preferences.currentHost, .uniform(20))
        XCTAssertEqual(preferences.appliedOperations.count, 1)  // only the apply
        XCTAssertNotNil(backups.record)
    }

    func testAnUnreadableBackupNeverProducesARestoreWrite() throws {
        backups.loadError = .unreadable("damaged")
        XCTAssertEqual(try coordinator.restore(), .unusableBackup)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
    }

    func testACorruptRecordNeverProducesARestoreWrite() throws {
        backups.record = BackupRecord(original: .uniform(9999), applied: .unset, capturedAt: fixedDate)
        XCTAssertEqual(try coordinator.restore(), .unusableBackup)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
    }

    func testRestoringWhenAlreadyOriginalClearsTheStaleRecord() throws {
        backups.record = BackupRecord(original: .unset, applied: .uniform(4), capturedAt: fixedDate)
        XCTAssertEqual(try coordinator.restore(), .alreadyOriginal)
        XCTAssertTrue(preferences.appliedOperations.isEmpty)
        XCTAssertNil(backups.record)
    }

    func testAnIgnoredRestoreIsReportedAndKeepsTheRecord() throws {
        _ = try coordinator.apply(.wide)
        preferences.readBackOverride = .uniform(24)  // the deletion does not take

        let outcome = try coordinator.restore()

        XCTAssertEqual(outcome, .noEffect(expected: .unset, actual: .uniform(24)))
        XCTAssertNotNil(backups.record)
    }

    // MARK: state

    func testStateNamesThePresetAndTheBackup() throws {
        preferences.anyHost = .uniform(6)
        _ = try coordinator.apply(.wide)

        let state = coordinator.state()
        XCTAssertEqual(state.currentHost, .uniform(24))
        XCTAssertEqual(state.anyHost, .uniform(6))
        XCTAssertEqual(state.preset, .wide)
        XCTAssertTrue(state.hasBackup)
        XCTAssertFalse(state.backupUnreadable)
    }

    func testStateReportsAValueWeDidNotProduce() {
        preferences.currentHost = .uniform(13)
        let state = coordinator.state()
        XCTAssertNil(state.preset)
        XCTAssertFalse(state.hasBackup)
    }

    func testStateReportsAnUnreadableBackupInsteadOfClaimingThereIsNone() {
        backups.loadError = .unreadable("damaged")
        let state = coordinator.state()
        XCTAssertFalse(state.hasBackup)
        XCTAssertTrue(state.backupUnreadable)
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

    func testSavingCreatesTheContainingDirectory() throws {
        try store.save(BackupRecord(original: .unset, applied: .uniform(4), capturedAt: Date()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
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
            guard case .unreadable = error as? BackupStoreError else {
                return XCTFail("expected .unreadable, got \(error)")
            }
        }
    }

    func testTheDefaultLocationIsTheAppsOwnApplicationSupportFolder() {
        let path = FileBackupStore.applicationSupport.path
        XCTAssertTrue(path.hasSuffix("/Application Support/jp.nlink.menubar-spacer/backup.json"), path)
    }
}
