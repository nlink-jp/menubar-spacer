import Foundation

/// The two undocumented global preference keys this app is allowed to touch.
/// Nothing else in the preference domain may ever be written.
enum SpacingKey: String, CaseIterable, Codable, Sendable {
    case spacing = "NSStatusItemSpacing"
    case selectionPadding = "NSStatusItemSelectionPadding"
}

/// A preference value this app can restore but not interpret — a string, a
/// float, a boolean, anything a person can put there with `defaults write`.
/// It is kept verbatim as a property list, because the record of what someone's
/// Mac held has to be faithful even when the value is not one we would produce.
struct OpaqueValue: Equatable, Codable, Sendable {
    /// A binary property list holding `[value]`; the single element is the value.
    let plist: Data
    /// For display only. Never used to reconstruct the value.
    let summary: String

    init(plist: Data, summary: String) {
        self.plist = plist
        self.summary = summary
    }

    /// Wraps the value in an array so any property-list type serialises,
    /// including a bare string or number.
    init?(capturing value: Any, summary: String) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: [value],
                                                             format: .binary, options: 0)
        else { return nil }
        self.init(plist: data, summary: summary)
    }

    /// The value as it was, or nil if the record cannot be unwrapped.
    var value: Any? {
        guard let list = try? PropertyListSerialization.propertyList(from: plist, options: [],
                                                                     format: nil),
              let array = list as? [Any], array.count == 1
        else { return nil }
        return array[0]
    }
}

/// One key's stored state. "Absent" is a distinct state from any value: on an
/// untouched Mac both keys are absent, and restoring means deleting them again
/// rather than writing a number that happens to look like the default.
enum StoredValue: Equatable, Codable, Sendable {
    case absent
    case integer(Int)
    /// A value that is neither absent nor an integer. Preserved verbatim so a
    /// restore puts back exactly what was there.
    case other(OpaqueValue)

    var integerValue: Int? {
        if case let .integer(value) = self { return value }
        return nil
    }

    /// How to describe this value to a person.
    var summary: String {
        switch self {
        case .absent: return "unset"
        case let .integer(value): return String(value)
        case let .other(value): return value.summary
        }
    }
}

/// The state of both keys in one preference scope.
struct SpacingSettings: Equatable, Codable, Sendable {
    var spacing: StoredValue
    var selectionPadding: StoredValue

    static let unset = SpacingSettings(spacing: .absent, selectionPadding: .absent)

    /// Both keys carrying the same value, which is the only combination the
    /// hardware checks measured. `nil` means both absent.
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

    /// The common value when both keys agree; `nil` when they differ, when only
    /// one is set, or when either holds something this app cannot interpret.
    /// Such a state is reachable with `defaults write`, so the UI has to be able
    /// to describe it rather than assume it away.
    var uniformValue: Int? {
        guard case let .integer(spacing) = spacing,
              case let .integer(padding) = selectionPadding,
              spacing == padding
        else { return nil }
        return spacing
    }

    /// True when every key holds a value this app can write back.
    var isRestorable: Bool {
        SpacingKey.allCases.allSatisfy { key in
            if case let .other(value) = self[key] { return value.value != nil }
            return true
        }
    }
}

/// A single preference mutation. The app never emits any other kind.
enum WriteOperation: Equatable, Sendable {
    case set(key: SpacingKey, value: StoredValue)
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
            case .integer, .other:
                return .set(key: key, value: target[key])
            }
        }
    }
}
