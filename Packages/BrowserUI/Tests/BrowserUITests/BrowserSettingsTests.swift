import Foundation
import Testing

@testable import BrowserUI

@Suite struct BrowserSettingsTests {
  /// A suite of its own, removed afterwards, so a test never reads or writes
  /// the app's real settings.
  private func suite() throws -> (UserDefaults, cleanup: () -> Void) {
    let name = "BrowserSettingsTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return (defaults, { defaults.removePersistentDomain(forName: name) })
  }

  @Test func openFoldersAreRememberedUntilTheSettingIsTurnedOff() throws {
    let (defaults, cleanup) = try suite()
    defer { cleanup() }
    #expect(BrowserSettings(defaults: defaults).rememberOpenFolders)

    defaults.set(false, forKey: BrowserSettings.rememberOpenFoldersKey)
    #expect(!BrowserSettings(defaults: defaults).rememberOpenFolders)

    defaults.set(true, forKey: BrowserSettings.rememberOpenFoldersKey)
    #expect(BrowserSettings(defaults: defaults).rememberOpenFolders)
  }

  @Test func aValueWrittenThroughTheSettingsIsReadBack() throws {
    let (defaults, cleanup) = try suite()
    defer { cleanup() }
    let settings = BrowserSettings(defaults: defaults)

    settings.rememberOpenFolders = false
    #expect(!settings.rememberOpenFolders)
    #expect(!BrowserSettings(defaults: defaults).rememberOpenFolders)
    #expect(defaults.object(forKey: BrowserSettings.rememberOpenFoldersKey) as? Bool == false)

    settings.rememberOpenFolders = true
    #expect(BrowserSettings(defaults: defaults).rememberOpenFolders)
  }

  @Test func twoSuitesDoNotSeeEachOther() throws {
    let (first, cleanFirst) = try suite()
    let (second, cleanSecond) = try suite()
    defer {
      cleanFirst()
      cleanSecond()
    }
    BrowserSettings(defaults: first).rememberOpenFolders = false
    #expect(BrowserSettings(defaults: second).rememberOpenFolders)
  }

  @Test func theKeyIsNamedForTheSettingAndNothingElseUsesIt() {
    #expect(BrowserSettings.rememberOpenFoldersKey == "RememberOpenFolders")
    #expect(BrowserSettings.rememberOpenFoldersKey != InitialLocation.argumentKey)
  }
}
