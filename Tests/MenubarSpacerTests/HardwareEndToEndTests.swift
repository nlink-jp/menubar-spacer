import XCTest
@testable import MenubarSpacer

/// The only test that touches the real preference domain, and the only one that
/// exercises `SystemSpacingPreferences` — including the partial write that the
/// measurement probe never performed, since the probe always wrote both keys.
///
/// Opt-in: `make test` never runs it.
///
///     MENUBAR_SPACER_HARDWARE_TEST=1 swift test --filter HardwareEndToEndTests
///
/// It refuses to run unless both keys are absent to begin with, so it can never
/// destroy a value someone else set, and it deletes both keys in teardown
/// whatever happened in between.
final class HardwareEndToEndTests: XCTestCase {
    private var preferences: SystemSpacingPreferences!
    private var directory: URL!
    private var coordinator: SpacingCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MENUBAR_SPACER_HARDWARE_TEST"] == "1",
                          "opt-in hardware test; set MENUBAR_SPACER_HARDWARE_TEST=1")

        preferences = SystemSpacingPreferences()
        try XCTSkipUnless(preferences.read(.currentHost) == .unset,
                          "refusing to run: the spacing keys are already set on this Mac")

        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("menubar-spacer-e2e-" + UUID().uuidString, isDirectory: true)
        coordinator = SpacingCoordinator(
            preferences: preferences,
            backups: FileBackupStore(url: directory.appendingPathComponent("backup.json"))
        )
    }

    override func tearDownWithError() throws {
        if let preferences {
            // Unconditional: whatever the test did, this Mac goes back to the
            // state it was required to be in before the test started.
            _ = try? preferences.apply(SpacingKey.allCases.map { .delete(key: $0) })
            XCTAssertEqual(preferences.read(.currentHost), .unset, "failed to clean up the spacing keys")
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testApplyAndRestoreAgainstTheRealPreferenceDomain() throws {
        XCTAssertEqual(try coordinator.apply(.minimum), .applied(.uniform(4)))
        XCTAssertEqual(preferences.read(.currentHost), .uniform(4))
        XCTAssertEqual(preferences.read(.anyHost), .unset, "the any-host scope must never be written")

        XCTAssertEqual(try coordinator.apply(.minimum), .alreadyApplied(.uniform(4)))

        XCTAssertEqual(try coordinator.apply(.wide), .applied(.uniform(24)))
        XCTAssertEqual(preferences.read(.currentHost), .uniform(24))

        XCTAssertEqual(try coordinator.restore(), .restored(.unset))
        XCTAssertEqual(preferences.read(.currentHost), .unset)
        XCTAssertEqual(preferences.read(.anyHost), .unset)
    }

    /// `CFPreferencesSetMultiple` with only one key named in each list: the shape
    /// the minimal write plan produces, and the one the probe never exercised.
    func testWritingASingleKeyLeavesTheOtherUntouched() throws {
        _ = try preferences.apply([.set(key: .spacing, value: .integer(8))])
        XCTAssertEqual(preferences.read(.currentHost),
                       SpacingSettings(spacing: .integer(8), selectionPadding: .absent))

        _ = try preferences.apply([.set(key: .selectionPadding, value: .integer(8))])
        XCTAssertEqual(preferences.read(.currentHost), .uniform(8))

        _ = try preferences.apply([.delete(key: .spacing)])
        XCTAssertEqual(preferences.read(.currentHost),
                       SpacingSettings(spacing: .absent, selectionPadding: .integer(8)))

        // And the coordinator's plan fills in just the missing key.
        XCTAssertEqual(try coordinator.apply(.narrow), .applied(.uniform(8)))
    }

    /// Values a person can put there with `defaults write` that this app would
    /// never produce. Before the read layer preserved them, a string read as
    /// "absent" — so Restore would have deleted a key the user had set.
    func testValuesTheAppCannotInterpretAreReadAndRestoredVerbatim() throws {
        let text = try XCTUnwrap(OpaqueValue(capturing: "8", summary: "text \"8\""))
        _ = try preferences.apply([.set(key: .spacing, value: .other(text))])

        let read = preferences.read(.currentHost).spacing
        guard case let .other(value) = read else {
            return XCTFail("a string value must not read as \(read)")
        }
        XCTAssertEqual(value.value as? String, "8")

        // And it survives being recorded as the original and put back.
        XCTAssertEqual(try coordinator.apply(.wide), .applied(.uniform(24)))
        XCTAssertEqual(try coordinator.restore(),
                       .restored(SpacingSettings(spacing: .other(value), selectionPadding: .absent)))
        XCTAssertEqual(preferences.read(.currentHost).spacing.summary, "text \"8\"")
    }

    func testADecimalIsNotSilentlyTruncated() throws {
        let decimal = try XCTUnwrap(OpaqueValue(capturing: 12.5, summary: "decimal 12.5"))
        _ = try preferences.apply([.set(key: .spacing, value: .other(decimal))])

        guard case let .other(value) = preferences.read(.currentHost).spacing else {
            return XCTFail("a decimal must not read as an integer")
        }
        XCTAssertEqual(value.value as? Double, 12.5)
    }

    func testAnEmptyPlanWritesNothing() throws {
        XCTAssertEqual(try preferences.apply([]), .unset)
        XCTAssertEqual(preferences.read(.currentHost), .unset)
    }
}
