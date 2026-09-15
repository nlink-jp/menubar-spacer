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
        let decision = RestorePlanner.decide(record: backup, current: .uniform(4))
        XCTAssertEqual(decision, .restore([
            .delete(key: .spacing),
            .delete(key: .selectionPadding),
        ]))
    }

    func testRestoringPutsBackAPreexistingValue() {
        let backup = record(original: .uniform(12), applied: .uniform(4))
        let decision = RestorePlanner.decide(record: backup, current: .uniform(4))
        XCTAssertEqual(decision, .restore([
            .set(key: .spacing, value: 12),
            .set(key: .selectionPadding, value: 12),
        ]))
    }

    func testAlreadyOriginalIsNotAWrite() {
        let backup = record(original: .unset, applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .unset), .alreadyOriginal)
    }

    func testAnExternalChangeIsNotSilentlyOverwritten() {
        let backup = record(original: .unset, applied: .uniform(4))
        let decision = RestorePlanner.decide(record: backup, current: .uniform(20))
        XCTAssertEqual(decision, .changedExternally(current: .uniform(20), original: .unset))
    }

    func testACorruptBackupNeverProducesAWrite() {
        let backup = record(original: .uniform(9999), applied: .uniform(4))
        XCTAssertEqual(RestorePlanner.decide(record: backup, current: .uniform(4)), .unusableBackup)
    }

    func testBackupRoundTripsThroughJSON() throws {
        let backup = record(original: SpacingSettings(spacing: .integer(6), selectionPadding: .absent),
                            applied: .uniform(24))
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(BackupRecord.self, from: data)
        XCTAssertEqual(decoded, backup)
    }
}
