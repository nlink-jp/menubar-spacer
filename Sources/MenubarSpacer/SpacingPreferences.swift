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

/// Reads the two keys from the current user's global preference domain
/// (`kCFPreferencesAnyApplication`), which is the scope the feasibility study
/// validated.
struct SystemSpacingPreferences: SpacingPreferenceReading {
    func read(_ scope: PreferenceScope) -> SpacingSettings {
        var settings = SpacingSettings.unset
        for key in SpacingKey.allCases {
            settings[key] = Self.value(for: key, scope: scope)
        }
        return settings
    }

    private static func value(for key: SpacingKey, scope: PreferenceScope) -> StoredValue {
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

/// A reader backed by an in-memory state, for tests and previews.
struct StubSpacingPreferences: SpacingPreferenceReading {
    var currentHost: SpacingSettings = .unset
    var anyHost: SpacingSettings = .unset

    func read(_ scope: PreferenceScope) -> SpacingSettings {
        switch scope {
        case .currentHost: return currentHost
        case .anyHost: return anyHost
        }
    }
}
