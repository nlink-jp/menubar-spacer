import XCTest
@testable import MenubarSpacer

final class RestorePlannerTests: XCTestCase {
    private func record(original: SpacingSettings, applied: SpacingSettings) -> BackupRecord {
        BackupRecord(original: original, applied: applied, capturedAt: Date(timeIntervalSince1970: 0))
    }

    func testNothingToRestoreWithoutABackup() {
        XCTAssertEqual(RestorePlanner.decide(record: nil, current: .uniform(4)), .noBackup)
    }

    func testRestoringDeletesKeysThatWereOriginallyAbsent() {
        let backup = record(original: .unset, applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .uniform(4)), .restore([
            .delete(key: .spacing),
            .delete(key: .selectionPadding),
        ]))
    }

    func testRestoringPutsBackAPreexistingValue() {
        let backup = record(original: .uniform(12), applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .uniform(4)), .restore([
            .set(key: .spacing, value: .integer(12)),
            .set(key: .selectionPadding, value: .integer(12)),
        ]))
    }

    func testAnUnusualValueIsRestoredLikeAnyOther() {
        // A hand-set 100 is the user's state, not corruption. Refusing to restore
        // it would strand the only Mac that needs restoring most.
        let backup = record(original: .uniform(100), applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .uniform(4)), .restore([
            .set(key: .spacing, value: .integer(100)),
            .set(key: .selectionPadding, value: .integer(100)),
        ]))
    }

    func testAnOriginalThatCannotBeWrittenBackIsReportedNotAttempted() {
        let broken = StoredValue.other(OpaqueValue(plist: Data(), summary: "an unsupported value"))
        let original = SpacingSettings(spacing: broken, selectionPadding: .absent)
        let backup = record(original: original, applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .uniform(4)),
                       .unrestorableOriginal(original))
    }

    func testAlreadyOriginalIsNotAWrite() {
        let backup = record(original: .unset, applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .unset), .alreadyOriginal)
    }

    func testAnExternalChangeIsNotSilentlyOverwritten() {
        let backup = record(original: .unset, applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .uniform(20)),
                       .changedExternally(current: .uniform(20), original: .unset))
    }

    /// The case that made the app blame an outsider for its own half-finished
    /// write: one key landed, the other did not.
    func testAHalfLandedWriteIsOursToCleanUp() {
        let backup = record(original: .uniform(12), applied: .uniform(24))
        let half = SpacingSettings(spacing: .integer(24), selectionPadding: .integer(12))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: half),
                       .restore([.set(key: .spacing, value: .integer(12))]))
    }

    func testAHalfLandedRestoreCanBeResumed() {
        // After a restore that only deleted one key, the record describes that
        // state, and pressing Restore again must finish the job.
        let backup = record(original: .unset,
                            applied: SpacingSettings(spacing: .absent, selectionPadding: .integer(4)))
        let current = SpacingSettings(spacing: .absent, selectionPadding: .integer(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: current),
                       .restore([.delete(key: .selectionPadding)]))
    }

    func testAMixOfOurTwoStatesStillCountsAsOurs() {
        let backup = record(original: .uniform(12), applied: .uniform(24))
        XCTAssertTrue(RestorePlanner.isExplainedByOurWrite(
            current: SpacingSettings(spacing: .integer(12), selectionPadding: .integer(24)),
            record: backup))
        XCTAssertFalse(RestorePlanner.isExplainedByOurWrite(
            current: SpacingSettings(spacing: .integer(30), selectionPadding: .integer(24)),
            record: backup))
    }

    func testBackupRoundTripsThroughJSON() throws {
        let backup = record(original: SpacingSettings(spacing: .integer(6), selectionPadding: .absent),
                            applied: .uniform(24))
        let data = try JSONEncoder().encode(backup)
        XCTAssertEqual(try JSONDecoder().decode(BackupRecord.self, from: data), backup)
    }
}
