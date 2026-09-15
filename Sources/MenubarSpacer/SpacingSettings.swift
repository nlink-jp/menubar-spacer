import Foundation

/// The two undocumented global preference keys this app is allowed to touch.
/// Nothing else in the preference domain may ever be written.
enum SpacingKey: String, CaseIterable, Codable, Sendable {
    case spacing = "NSStatusItemSpacing"
    case selectionPadding = "NSStatusItemSelectionPadding"
}

/// One key's stored state. "Absent" is a distinct state from any value: on an
/// untouched Mac both keys are absent, and restoring means deleting them again
/// rather than writing a number that happens to look like the default.
enum StoredValue: Equatable, Codable, Sendable {
    case absent
    case integer(Int)

    var integerValue: Int? {
        if case let .integer(value) = self { return value }
        return nil
    }
}

/// The state of both keys in one preference scope.
struct SpacingSettings: Equatable, Codable, Sendable {
    var spacing: StoredValue
    var selectionPadding: StoredValue

    static let unset = SpacingSettings(spacing: .absent, selectionPadding: .absent)

    /// Both keys carrying the same value, which is the only combination the
    /// feasibility study measured. `nil` means both absent.
    static func uniform(_ value: Int?) -> SpacingSettings {
        guard let value else { return .unset }
        return SpacingSettings(spacing: .integer(value), selectionPadding: .integer(value))
    }

    subscript(key: SpacingKey) -> StoredValue {
        get {
            switch key {
            case .spacing: return spacing
            case .selectionPadding: return selectionPadding
            }
        }
        set {
            switch key {
            case .spacing: spacing = newValue
            case .selectionPadding: selectionPadding = newValue
            }
        }
    }

    /// The common value when both keys agree; `nil` when they differ or when only
    /// one of them is set. Such a state is reachable by editing `defaults` by
    /// hand, so the UI has to be able to describe it rather than assume it away.
    var uniformValue: Int? {
        guard case let .integer(spacing) = spacing,
              case let .integer(padding) = selectionPadding,
              spacing == padding
        else { return nil }
        return spacing
    }

    /// Guards against a corrupt backup file driving an absurd write. The bound is
    /// deliberately generous: only 4 and 24 were measured, and the point here is
    /// to reject garbage, not to encode a recommendation.
    var isPlausible: Bool {
        SpacingKey.allCases.allSatisfy { key in
            guard let value = self[key].integerValue else { return true }
            return (0...64).contains(value)
        }
    }
}

/// A single preference mutation. The app never emits any other kind.
enum WriteOperation: Equatable, Sendable {
    case set(key: SpacingKey, value: Int)
    case delete(key: SpacingKey)

    var key: SpacingKey {
        switch self {
        case let .set(key, _): return key
        case let .delete(key): return key
        }
    }
}

enum SpacingPlan {
    /// The operations that turn `current` into `target`, touching only the keys
    /// that actually differ. An already-correct key is never rewritten, so a
    /// no-op apply leaves the preference file untouched.
    static func operations(from current: SpacingSettings, to target: SpacingSettings) -> [WriteOperation] {
        SpacingKey.allCases.compactMap { key in
            guard current[key] != target[key] else { return nil }
            switch target[key] {
            case .absent:
                return .delete(key: key)
            case let .integer(value):
                return .set(key: key, value: value)
            }
        }
    }
}
