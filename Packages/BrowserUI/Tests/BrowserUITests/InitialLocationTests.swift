import Foundation
import Testing

@testable import BrowserUI

@Suite struct InitialLocationTests {
  private let fallback = URL(filePath: "/Users/fallback", directoryHint: .isDirectory)

  @Test func usesTheFallbackWithoutAnArgument() throws {
    let empty = try #require(
      UserDefaults(suiteName: "InitialLocationTests-empty-\(UUID().uuidString)"))
    #expect(InitialLocation.resolve(defaults: empty, fallback: fallback) == fallback)
  }

  @Test func usesTheFolderNamedByTheArgument() throws {
    let name = "InitialLocationTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }

    defaults.set("/tmp/some folder/../target", forKey: InitialLocation.argumentKey)
    #expect(InitialLocation.resolve(defaults: defaults, fallback: fallback).path == "/tmp/target")

    defaults.set("~/Documents", forKey: InitialLocation.argumentKey)
    #expect(
      InitialLocation.resolve(defaults: defaults, fallback: fallback).path
        == NSHomeDirectory() + "/Documents")

    defaults.set("", forKey: InitialLocation.argumentKey)
    #expect(InitialLocation.resolve(defaults: defaults, fallback: fallback) == fallback)
  }
}
