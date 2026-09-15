import AppKit
import XCTest
@testable import MenubarSpacer

/// The drawing is a scale drawing of a measured thing, so its numbers are pinned
/// to the measurement. If macOS changes what the keys do, these fail — which is
/// the point: a sample that no longer matches the photographs is worse than no
/// sample at all.
final class SpacingSampleTests: XCTestCase {
    /// Square status item window widths measured on macOS 27.0 (26A428),
    /// docs/en/preset-appearance.md.
    private let measured: [(value: Int?, width: CGFloat)] = [
        (nil, 38), (4, 26), (8, 30), (24, 46),
    ]

    func testEverySlotMatchesTheMeasuredWidth() {
        for (value, width) in measured {
            XCTAssertEqual(SpacingSample.slotWidth(for: value), width,
                           "value \(value.map(String.init) ?? "unset")")
        }
    }

    func testTheDefaultIsDrawnAsTheMeasuredSixteen() {
        XCTAssertEqual(SpacingSample.defaultValue, 16)
        XCTAssertEqual(SpacingSample.slotWidth(for: nil), SpacingSample.slotWidth(for: 16))
    }

    func testTheTotalsMatchThePhotographedStrips() {
        // Six icons, the same count the photographs used. The captured crops were
        // 186 / 210 / 258 / 306 px wide including a 6px margin on each side.
        for (value, expected) in [(4, 156.0), (8, 180.0), (nil as Int?, 228.0), (24, 276.0)]
            as [(Int?, Double)] {
            XCTAssertEqual(SpacingSample.totalWidth(for: value), CGFloat(expected))
        }
        for (value, captured) in [(4, 186.0), (8, 210.0), (nil as Int?, 258.0), (24, 306.0)]
            as [(Int?, Double)] {
            // The captures add the crop margin and the strip's own padding; the
            // difference must be the same constant at every preset, or the
            // drawing and the photograph disagree about more than margins.
            XCTAssertEqual(CGFloat(captured) - SpacingSample.totalWidth(for: value), 30)
        }
    }

    func testEveryPresetCanBeDrawn() {
        for preset in SpacingPreset.allCases {
            XCTAssertGreaterThan(SpacingSample.slotWidth(for: preset.value), 0)
        }
    }

    /// A symbol that does not resolve draws an empty slot — the geometry stays
    /// right and the drawing looks broken, which is the worst failure mode for
    /// something whose whole job is to be believed.
    func testEverySampleSymbolExists() {
        XCTAssertEqual(SpacingSampleRow.symbols.count, SpacingSample.iconCount)
        for symbol in SpacingSampleRow.symbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                            "no such SF Symbol: \(symbol)")
        }
    }

    func testAStateWeDidNotProduceIsNotDrawn() {
        // Nothing sensible to draw: saying so beats inventing a spacing.
        let mixed = SpacingSettings(spacing: .integer(4), selectionPadding: .absent)
        XCTAssertNil(SpacingSample.value(of: mixed))
        XCTAssertEqual(SpacingSample.value(of: .unset), .some(nil))
        XCTAssertEqual(SpacingSample.value(of: .uniform(8)), .some(8))
    }
}
