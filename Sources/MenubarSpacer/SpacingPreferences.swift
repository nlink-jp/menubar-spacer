import CoreFoundation
import Foundation

/// The preference scopes this app reads. Only `.currentHost` is ever written;
/// `.anyHost` is read so the UI can show a value set there by some other means,
/// which would otherwise look like the app's write had no effect.
enum PreferenceScope: Sendable {
    case currentHost
    case anyHost

    var host: CFString {
        switch self {
        case .currentHost: return kCFPreferencesCurrentHost
        case .anyHost: return kCFPreferencesAnyHost
        }
    }
}

/// Read access to the spacing keys. A protocol so the app's logic can be tested
/// without touching the real preference domain.
protocol SpacingPreferenceReading {
    func read(_ scope: PreferenceScope) -> SpacingSettings
}

/// Write access, always verified: the implementation reads the scope back and
/// reports what it actually found rather than assuming the write landed. These
/// keys are undocumented, so "the OS ignored us" is a state the product has to
/// be able to describe.
protocol SpacingPreferenceWriting {
    @discardableResult
    func apply(_ operations: [WriteOperation]) throws -> SpacingSettings
}

enum SpacingWriteError: Error, Equatable {
    /// The flush failed. `CFPreferencesSetMultiple` has already run by then, so
    /// the state read back afterwards travels with the error.
    case synchronizationFailed(actual: SpacingSettings)
    /// A recorded value could not be turned back into a property list.
    case unrestorableValue(SpacingKey)
}

/// Reads and writes the two keys in the current user's global preference domain
/// (`kCFPreferencesAnyApplication`), which is the scope the hardware checks
/// validated. Keys outside `SpacingKey` are unreachable from here by
/// construction: `WriteOperation` cannot name one.
struct SystemSpacingPreferences: SpacingPreferenceReading, SpacingPreferenceWriting {
    func read(_ scope: PreferenceScope) -> SpacingSettings {
        if scope == .currentHost {
            // Only the scope this app writes needs a flush before reading.
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                     scope.host)
        }
        var settings = SpacingSettings.unset
        for key in SpacingKey.allCases {
            settings[key] = Self.value(for: key, scope: scope)
        }
        return settings
    }

    @discardableResult
    func apply(_ operations: [WriteOperation]) throws -> SpacingSettings {
        var toSet: [String: Any] = [:]
        var toRemove: [String] = []
        for operation in operations {
            switch operation {
            case let .set(key, value):
                switch value {
                case .absent:
                    toRemove.append(key.rawValue)
                case let .integer(number):
                    toSet[key.rawValue] = number
                case let .other(opaque):
                    guard let raw = opaque.value else { throw SpacingWriteError.unrestorableValue(key) }
                    toSet[key.rawValue] = raw
                }
            case let .delete(key):
                toRemove.append(key.rawValue)
            }
        }

        // Keys named in neither list are left untouched, so an apply only ever
        // rewrites what actually differs.
        CFPreferencesSetMultiple(toSet as CFDictionary, toRemove as CFArray,
                                 kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                 kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                       kCFPreferencesCurrentHost) else {
            throw SpacingWriteError.synchronizationFailed(actual: read(.currentHost))
        }
        return read(.currentHost)
    }

    /// Reads one key losslessly. Anything that is not a plain integer — a string
    /// written by `defaults write -g … 8` without `-int`, a float, a boolean — is
    /// preserved verbatim instead of being coerced, because the record of what
    /// this Mac held has to be true even when the value is not one we produce.
    private static func value(for key: SpacingKey, scope: PreferenceScope) -> StoredValue {
        guard let raw = CFPreferencesCopyValue(
            key.rawValue as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            scope.host
        ) else { return .absent }

        // A CFBoolean also bridges to NSNumber, so the type id is checked first;
        // a float is left to the verbatim path rather than being truncated.
        let typeID = CFGetTypeID(raw)
        if typeID == CFNumberGetTypeID(), let number = raw as? NSNumber,
           !CFNumberIsFloatType(number as CFNumber) {
            return .integer(number.intValue)
        }
        let summary = Self.summarize(raw, typeID: typeID)
        guard let opaque = OpaqueValue(capturing: raw, summary: summary) else {
            return .other(OpaqueValue(plist: Data(), summary: summary))
        }
        return .other(opaque)
    }

    private static func summarize(_ raw: CFPropertyList, typeID: CFTypeID) -> String {
        if typeID == CFBooleanGetTypeID() {
            return "boolean \((raw as? NSNumber)?.boolValue == true ? "true" : "false")"
        }
        if typeID == CFNumberGetTypeID() {
            return "decimal \((raw as? NSNumber)?.stringValue ?? "?")"
        }
        if typeID == CFStringGetTypeID() {
            return "text \"\(raw as? String ?? "?")\""
        }
        return "an unsupported value"
    }
}

/// An in-memory stand-in for previews and tests. Keeping it beside the protocol
/// (as `instant-translate` does with its translator stub) means no test ever has
/// a reason to reach for the real preference domain.
final class StubSpacingPreferences: SpacingPreferenceReading, SpacingPreferenceWriting {
    var currentHost: SpacingSettings
    var anyHost: SpacingSettings
    /// Set to simulate an OS that accepts the write but does not honour it, or
    /// honours only part of it.
    var readBackOverride: SpacingSettings?
    var writeError: SpacingWriteError?
    private(set) var appliedOperations: [[WriteOperation]] = []
    /// Shared with a `StubBackupStore` so a test can assert the order of store
    /// calls and writes, not merely their counts.
    var journal: StubBackupStore?

    init(currentHost: SpacingSettings = .unset, anyHost: SpacingSettings = .unset) {
        self.currentHost = currentHost
        self.anyHost = anyHost
    }

    func read(_ scope: PreferenceScope) -> SpacingSettings {
        switch scope {
        case .currentHost: return currentHost
        case .anyHost: return anyHost
        }
    }

    @discardableResult
    func apply(_ operations: [WriteOperation]) throws -> SpacingSettings {
        journal?.note("write")
        appliedOperations.append(operations)
        if let writeError { throw writeError }
        for operation in operations {
            switch operation {
            case let .set(key, value): currentHost[key] = value
            case let .delete(key): currentHost[key] = .absent
            }
        }
        if let readBackOverride { currentHost = readBackOverride }
        return currentHost
    }
}
