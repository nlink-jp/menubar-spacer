import XCTest
@testable import MenubarSpacer

final class SpacingPlanTests: XCTestCase {
    func testUnsetIsBothKeysAbsent() {
        XCTAssertEqual(SpacingSettings.unset.spacing, .absent)
        XCTAssertEqual(SpacingSettings.unset.selectionPadding, .absent)
        XCTAssertEqual(SpacingSettings.uniform(nil), .unset)
    }

    func testApplyingAPresetSetsBothKeys() {
        let plan = SpacingPlan.operations(from: .unset, to: SpacingPreset.minimum.settings)
        XCTAssertEqual(plan, [
            .set(key: .spacing, value: .integer(4)),
            .set(key: .selectionPadding, value: .integer(4)),
        ])
    }

    func testReturningToOSDefaultDeletesBothKeys() {
        let plan = SpacingPlan.operations(from: .uniform(24), to: SpacingPreset.osDefault.settings)
        XCTAssertEqual(plan, [
            .delete(key: .spacing),
            .delete(key: .selectionPadding),
        ])
    }

    func testNoOperationsWhenAlreadyAtTheTarget() {
        XCTAssertTrue(SpacingPlan.operations(from: .uniform(8), to: .uniform(8)).isEmpty)
        XCTAssertTrue(SpacingPlan.operations(from: .unset, to: .unset).isEmpty)
    }

    func testOnlyTheDifferingKeyIsTouched() {
        let current = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        let plan = SpacingPlan.operations(from: current, to: .uniform(4))
        XCTAssertEqual(plan, [.set(key: .selectionPadding, value: .integer(4))])
    }

    func testAValueTheAppCannotInterpretIsStillPlanned() {
        // Restoring someone's hand-set string has to produce a write, not a gap.
        let opaque = StoredValue.other(OpaqueValue(capturing: "8", summary: "text \"8\"")!)
        let target = SpacingSettings(spacing: opaque, selectionPadding: .absent)
        XCTAssertEqual(SpacingPlan.operations(from: .unset, to: target),
                       [.set(key: .spacing, value: opaque)])
    }

    func testKeyNamesAreTheMeasuredOnes() {
        XCTAssertEqual(SpacingKey.spacing.rawValue, "NSStatusItemSpacing")
        XCTAssertEqual(SpacingKey.selectionPadding.rawValue, "NSStatusItemSelectionPadding")
        XCTAssertEqual(SpacingKey.allCases.count, 2)
    }

    func testUniformValueOnlyWhenBothKeysAgreeOnAnInteger() {
        XCTAssertEqual(SpacingSettings.uniform(8).uniformValue, 8)
        XCTAssertNil(SpacingSettings.unset.uniformValue)
        XCTAssertNil(SpacingSettings(spacing: .integer(4), selectionPadding: .integer(8)).uniformValue)
        XCTAssertNil(SpacingSettings(spacing: .integer(4), selectionPadding: .absent).uniformValue)
        let opaque = StoredValue.other(OpaqueValue(capturing: "4", summary: "text")!)
        XCTAssertNil(SpacingSettings(spacing: opaque, selectionPadding: .integer(4)).uniformValue)
    }

    func testAnyIntegerIsAcceptable() {
        // There is no "implausible" value: whatever a Mac holds is what has to
        // come back. A hand-set 100 is the user's, not corruption.
        XCTAssertTrue(SpacingSettings.uniform(100).isRestorable)
        XCTAssertTrue(SpacingSettings.uniform(-5).isRestorable)
        XCTAssertTrue(SpacingSettings.unset.isRestorable)
    }

    func testAValueThatCannotBeReconstructedIsNotRestorable() {
        let broken = StoredValue.other(OpaqueValue(plist: Data(), summary: "an unsupported value"))
        XCTAssertFalse(SpacingSettings(spacing: broken, selectionPadding: .absent).isRestorable)
    }
}

final class OpaqueValueTests: XCTestCase {
    func testAStringRoundTrips() throws {
        let value = try XCTUnwrap(OpaqueValue(capturing: "8", summary: "text \"8\""))
        XCTAssertEqual(value.value as? String, "8")
    }

    func testADecimalRoundTripsWithoutTruncation() throws {
        let value = try XCTUnwrap(OpaqueValue(capturing: 12.5, summary: "decimal 12.5"))
        XCTAssertEqual(value.value as? Double, 12.5)
    }

    func testItSurvivesTheBackupFileFormat() throws {
        let value = try XCTUnwrap(OpaqueValue(capturing: "8", summary: "text \"8\""))
        let settings = SpacingSettings(spacing: .other(value), selectionPadding: .absent)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(SpacingSettings.self, from: data), settings)
    }
}

final class SpacingPresetTests: XCTestCase {
    func testPresetValues() {
        XCTAssertEqual(SpacingPreset.minimum.value, 4)
        XCTAssertEqual(SpacingPreset.narrow.value, 8)
        XCTAssertNil(SpacingPreset.osDefault.value)
        XCTAssertEqual(SpacingPreset.wide.value, 24)
    }

    func testMatchingRecognisesEachPreset() {
        for preset in SpacingPreset.allCases {
            XCTAssertEqual(SpacingPreset.matching(preset.settings), preset)
        }
    }

    func testMatchingRejectsAStateWeDidNotProduce() {
        XCTAssertNil(SpacingPreset.matching(.uniform(13)))
        XCTAssertNil(SpacingPreset.matching(SpacingSettings(spacing: .integer(4), selectionPadding: .integer(24))))
    }
}

/// The strings a person reads. They must not expose the app's own vocabulary —
/// key names, "absent", build status — only what the situation means.
final class SpacingDescriptionTests: XCTestCase {
    func testTheUntouchedStateIsNamedAfterMacOSNotOurKeys() {
        XCTAssertEqual(SpacingDescription.spacing(.unset), "macOS default")
    }

    func testAValueReadsAsItsNumber() {
        XCTAssertEqual(SpacingDescription.spacing(.uniform(8)), "8")
    }

    func testAStateWeDidNotProduceIsExplainedNotDumped() {
        let mixed = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        XCTAssertEqual(SpacingDescription.spacing(mixed), "set outside this app")
    }

    func testBackupStatusIsPhrasedForAPerson() {
        XCTAssertEqual(SpacingDescription.backup(.absent), "nothing to undo")
        XCTAssertEqual(SpacingDescription.backup(.present), "yes")
        XCTAssertEqual(SpacingDescription.backup(.unreadable), "the saved original cannot be read")
    }

    func testNoUserFacingStringNamesAPreferenceKey() {
        let strings = [SpacingDescription.spacing(.unset), SpacingDescription.spacing(.uniform(8)),
                       SpacingDescription.spacing(SpacingSettings(spacing: .integer(4), selectionPadding: .absent)),
                       SpacingDescription.backup(.absent), SpacingDescription.backup(.present),
                       SpacingDescription.backup(.unreadable)]
            + SpacingPreset.allCases.map(\.title)
        for string in strings {
            XCTAssertFalse(string.contains("NSStatusItem"), string)
            XCTAssertFalse(string.lowercased().contains("absent"), string)
            XCTAssertFalse(string.lowercased().contains("key"), string)
        }
    }
}

final class AppInfoTests: XCTestCase {
    func testAMissingBundleVersionReadsAsDev() {
        XCTAssertEqual(AppInfo.version(bundleValue: nil), "dev")
        XCTAssertEqual(AppInfo.version(bundleValue: ""), "dev")
        XCTAssertEqual(AppInfo.version(bundleValue: "  "), "dev")
        XCTAssertEqual(AppInfo.version(bundleValue: 3), "dev")
    }

    func testARealVersionIsShownVerbatim() {
        XCTAssertEqual(AppInfo.version(bundleValue: "0.1.0"), "0.1.0")
    }
}
