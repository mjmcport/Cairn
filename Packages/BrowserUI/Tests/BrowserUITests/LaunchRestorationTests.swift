import Foundation
import Testing

@testable import BrowserUI

/// Whether a launch reads and keeps saved state
/// (plans/phase-1a-step-10-state-restoration.md, U4: R13, R15, R16).
@Suite struct LaunchRestorationTests {
  private final class Memory: StateStoring {
    var data: Data?
    var saves = 0
    func load() -> Data? { data }
    func save(_ data: Data) {
      self.data = data
      saves += 1
    }
    func clear() { data = nil }
  }

  private struct Rig {
    let arguments: UserDefaults
    let settings: BrowserSettings
    let store: Memory
    let cleanup: () -> Void
  }

  private func rig() throws -> Rig {
    let a = "LaunchRestorationTests-args-\(UUID().uuidString)"
    let s = "LaunchRestorationTests-settings-\(UUID().uuidString)"
    let arguments = try #require(UserDefaults(suiteName: a))
    let settings = try #require(UserDefaults(suiteName: s))
    let store = Memory()
    store.data = SavedState(windows: [SavedWindow(tabs: [SavedTab(location: "file:///a/")])])
      .encoded()
    return Rig(
      arguments: arguments, settings: BrowserSettings(defaults: settings), store: store,
      cleanup: {
        arguments.removePersistentDomain(forName: a)
        settings.removePersistentDomain(forName: s)
      })
  }

  private func launch(_ rig: Rig) -> LaunchRestoration {
    LaunchRestoration(arguments: rig.arguments, settings: rig.settings, store: rig.store)
  }

  @Test func aPlainLaunchRestoresTheSavedWindow() throws {
    let rig = try rig()
    defer { rig.cleanup() }
    let launch = launch(rig)
    #expect(launch.isActive)
    #expect(launch.window?.tabs.first?.location == "file:///a/")
    #expect(!launch.hasNamedFolder)
  }

  @Test func openFolderIgnoresSavedStateAndLeavesItAlone() throws {
    let rig = try rig()
    defer { rig.cleanup() }
    rig.arguments.set("/somewhere", forKey: InitialLocation.argumentKey)
    let before = rig.store.data
    let launch = launch(rig)
    #expect(launch.window == nil)
    #expect(!launch.isActive)
    #expect(launch.hasNamedFolder)
    #expect(rig.store.data == before)
    #expect(rig.store.saves == 0)
  }

  @Test func theSettingOffRestoresNothing() throws {
    let rig = try rig()
    defer { rig.cleanup() }
    rig.settings.restoresWindows = false
    let launch = launch(rig)
    #expect(launch.window == nil)
    #expect(!launch.isActive)
  }

  @Test func damagedOrOldStateIsIgnoredAndNotDeleted() throws {
    let rig = try rig()
    defer { rig.cleanup() }
    rig.store.data = Data("garbage".utf8)
    let launch = launch(rig)
    #expect(launch.window == nil)
    #expect(launch.isActive)
    #expect(rig.store.data == Data("garbage".utf8))
  }

  @Test func theSuiteNameIsReported() throws {
    let rig = try rig()
    defer { rig.cleanup() }
    #expect(launch(rig).suite == nil)
    rig.arguments.set("Tests", forKey: UserDefaultsStateStore.suiteArgument)
    #expect(launch(rig).suite == "Tests")
  }
}
