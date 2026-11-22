import ByeSlidesCore
import Foundation

/// The app's bundle identifier used to be `studio.ciyuan.Ink`. Its typography settings are
/// copied once into the current domain so they survive the rename.
enum PreferencesMigration {
    static let formerDomain = "studio.ciyuan.Ink"
    static let doneKey = "migratedFormerPreferences"

    static func run(defaults: UserDefaults = .standard, from domain: String = formerDomain) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard let former = defaults.persistentDomain(forName: domain) else { return }
        for setting in TypographySetting.all where defaults.object(forKey: setting.key) == nil {
            if let value = former[setting.key] as? Int { defaults.set(value, forKey: setting.key) }
        }
    }
}
