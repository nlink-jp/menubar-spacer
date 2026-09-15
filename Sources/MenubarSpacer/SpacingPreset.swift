import Foundation

/// The four choices offered in the UI. Both keys always move together: the
/// feasibility study only ever measured them changed in lockstep, so a preset is
/// one number, not two.
///
/// Measured on macOS 27.0 (26A428) with an AppKit fixture whose text item had an
/// intrinsic width of 21pt: window width was 37 with the keys absent, 25 at 4/4
/// and 45 at 24/24 — i.e. `width ≈ intrinsic + N`, putting the OS default near
/// N ≈ 16. Only 4 and 24 are measured points; `narrow` is interpolated and is a
/// Phase 1 hardware check, not an established value.
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

    /// True when the value has been measured on hardware rather than derived.
    var isMeasured: Bool {
        switch self {
        case .minimum, .wide, .osDefault: return true
        case .narrow: return false
        }
    }

    /// The preset matching a live preference state, or `nil` when the state came
    /// from somewhere else (a hand-edited `defaults` write, another tool).
    static func matching(_ settings: SpacingSettings) -> SpacingPreset? {
        allCases.first { $0.settings == settings }
    }
}
