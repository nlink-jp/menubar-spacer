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
    case synchronizationFailed
    /// The write went through but the scope does not hold what was asked for.
    case readBackMismatch(expected: SpacingSettings, actual: SpacingSettings)
}

/// Reads and writes the two keys in the current user's global preference domain
/// (`kCFPreferencesAnyApplication`), which is the scope the hardware checks
/// validated. Keys outside `SpacingKey` are unreachable from here by
/// construction: `WriteOperation` cannot name one.
struct SystemSpacingPreferences: SpacingPreferenceReading, SpacingPreferenceWriting {
    func read(_ scope: PreferenceScope) -> SpacingSettings {
        var settings = SpacingSettings.unset
        for key in SpacingKey.allCases {
            settings[key] = Self.value(for: key, scope: scope)
        }
        return settings
    }

    @discardableResult
    func apply(_ operations: [WriteOperation]) throws -> SpacingSettings {
        var toSet: [String: Int] = [:]
        var toRemove: [String] = []
        for operation in operations {
            switch operation {
            case let .set(key, value): toSet[key.rawValue] = value
            case let .delete(key): toRemove.append(key.rawValue)
            }
        }

        // Keys named in neither list are left untouched, so an apply only ever
        // rewrites what actually differs.
        CFPreferencesSetMultiple(toSet as CFDictionary, toRemove as CFArray,
                                 kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                 kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                       kCFPreferencesCurrentHost) else {
            throw SpacingWriteError.synchronizationFailed
        }
        return read(.currentHost)
    }

    private static func value(for key: SpacingKey, scope: PreferenceScope) -> StoredValue {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, scope.host)
        let raw = CFPreferencesCopyValue(
            key.rawValue as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            scope.host
        )
        guard let number = raw as? NSNumber else { return .absent }
        return .integer(number.intValue)
    }
}

/// An in-memory stand-in for previews and tests. Keeping it beside the protocol
/// (as `instant-translate` does with its translator stub) means no test ever has
/// a reason to reach for the real preference domain.
final class StubSpacingPreferences: SpacingPreferenceReading, SpacingPreferenceWriting {
    var currentHost: SpacingSettings
    var anyHost: SpacingSettings
    /// Set to simulate an OS that accepts the write but does not honour it.
    var readBackOverride: SpacingSettings?
    var writeError: SpacingWriteError?
    private(set) var appliedOperations: [[WriteOperation]] = []

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
        appliedOperations.append(operations)
        if let writeError { throw writeError }
        for operation in operations {
            switch operation {
            case let .set(key, value): currentHost[key] = .integer(value)
            case let .delete(key): currentHost[key] = .absent
            }
        }
        if let readBackOverride { currentHost = readBackOverride }
        return currentHost
    }
}
