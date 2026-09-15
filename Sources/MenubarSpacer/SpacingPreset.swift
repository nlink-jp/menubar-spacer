import Foundation

/// The four choices offered in the UI. Both keys always move together: the
/// feasibility study only ever measured them changed in lockstep, so a preset is
/// one number, not two.
///
/// All four values were measured on macOS 27.0 (26A428) with an AppKit fixture
/// whose text item has an intrinsic width of 21pt. Window width per value:
///
///     unset → 37,  4 → 25,  8 → 29,  24 → 45
///
/// i.e. `width ≈ intrinsic + N`, which puts the OS default near N ≈ 16. Two
/// independent runs produced identical numbers; see docs/en/phase1-results.md.
enum SpacingPreset: String, CaseIterable, Identifiable, Sendable {
    case minimum
    case narrow
    case osDefault
    case wide

    var id: String { rawValue }

    /// The value written to both keys; `nil` means both keys are deleted.
    var value: Int? {
        switch self {
        case .minimum: return 4
        case .narrow: return 8
        case .osDefault: return nil
        case .wide: return 24
        }
    }

    var settings: SpacingSettings { .uniform(value) }

    /// The preset matching a live preference state, or `nil` when the state came
    /// from somewhere else (a hand-edited `defaults` write, another tool).
    static func matching(_ settings: SpacingSettings) -> SpacingPreset? {
        allCases.first { $0.settings == settings }
    }
}
