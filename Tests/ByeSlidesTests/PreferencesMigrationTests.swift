import Foundation
import Testing
@testable import ByeSlides
@testable import ByeSlidesCore

struct PreferencesMigrationTests {
    @Test func copiesTypographySettingsFromTheFormerBundleIdentifier() throws {
        let id = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: "bs-test-\(id)"))
        let former = "bs-test-former-\(id)"
        defaults.setPersistentDomain(["editorFontSize": 20, "readerSpacingTenths": 19, "unrelated": "x"], forName: former)
        defaults.set(14, forKey: TypographySetting.readerFontSize.key)
        defer {
            defaults.removePersistentDomain(forName: former)
            defaults.removePersistentDomain(forName: "bs-test-\(id)")
        }

        PreferencesMigration.run(defaults: defaults, from: former)
        #expect(defaults.integer(forKey: "editorFontSize") == 20)
        #expect(defaults.integer(forKey: "readerSpacingTenths") == 19)
        #expect(defaults.integer(forKey: "readerFontSize") == 14, "Settings already made in the new app win.")
        #expect(defaults.object(forKey: "unrelated") == nil)

        defaults.set(22, forKey: "editorFontSize")
        PreferencesMigration.run(defaults: defaults, from: former)
        #expect(defaults.integer(forKey: "editorFontSize") == 22, "Migration runs once.")
    }
}
