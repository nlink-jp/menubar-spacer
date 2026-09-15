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
            .set(key: .spacing, value: 4),
            .set(key: .selectionPadding, value: 4),
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
        XCTAssertEqual(plan, [.set(key: .selectionPadding, value: 4)])
    }

    func testKeyNamesAreTheMeasuredOnes() {
        XCTAssertEqual(SpacingKey.spacing.rawValue, "NSStatusItemSpacing")
        XCTAssertEqual(SpacingKey.selectionPadding.rawValue, "NSStatusItemSelectionPadding")
        XCTAssertEqual(SpacingKey.allCases.count, 2)
    }

    func testAbsurdValuesAreRejected() {
        XCTAssertTrue(SpacingSettings.uniform(0).isPlausible)
        XCTAssertTrue(SpacingSettings.uniform(64).isPlausible)
        XCTAssertFalse(SpacingSettings.uniform(65).isPlausible)
        XCTAssertFalse(SpacingSettings.uniform(-1).isPlausible)
        XCTAssertTrue(SpacingSettings.unset.isPlausible)
    }

    func testUniformValueOnlyWhenBothKeysAgree() {
        XCTAssertEqual(SpacingSettings.uniform(8).uniformValue, 8)
        XCTAssertNil(SpacingSettings.unset.uniformValue)
        XCTAssertNil(SpacingSettings(spacing: .integer(4), selectionPadding: .integer(8)).uniformValue)
        XCTAssertNil(SpacingSettings(spacing: .integer(4), selectionPadding: .absent).uniformValue)
    }
}

final class SpacingPresetTests: XCTestCase {
    func testPresetValues() {
        XCTAssertEqual(SpacingPreset.minimum.value, 4)
        XCTAssertEqual(SpacingPreset.narrow.value, 8)
        XCTAssertNil(SpacingPreset.osDefault.value)
        XCTAssertEqual(SpacingPreset.wide.value, 24)
    }

    func testOnlyMeasuredPresetsClaimToBeMeasured() {
        // 4 and 24 were measured on macOS 27.0; 8 is interpolated and must not
        // be presented as if it had been observed.
        XCTAssertFalse(SpacingPreset.narrow.isMeasured)
        XCTAssertTrue(SpacingPreset.minimum.isMeasured)
        XCTAssertTrue(SpacingPreset.wide.isMeasured)
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
