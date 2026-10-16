import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The saver's timing, with timers fired by hand so no test waits on a clock
/// (plans/phase-1a-step-10-state-restoration.md, U3).
@Suite @MainActor struct StateSaverTests {
  final class MemoryStore: StateStoring {
    var data: Data?
    var saves = 0
    var clears = 0
    func load() -> Data? { data }
    func save(_ data: Data) {
      self.data = data
      saves += 1
    }
    func clear() {
      data = nil
      clears += 1
    }
  }

  /// Timers that run only when the test fires them.
  @MainActor final class ManualClock {
    struct Timer {
      let id: Int
      let delay: Duration
      let fire: @MainActor () -> Void
    }
    var timers: [Timer] = []
    private var next = 0

    var scheduler: StateSaver.Scheduler {
      { [self] delay, fire in
        next += 1
        let id = next
        timers.append(Timer(id: id, delay: delay, fire: fire))
        return { [self] in timers.removeAll { $0.id == id } }
      }
    }

    /// Fires the live timer that waits `delay`.
    func fire(_ delay: Duration) {
      guard let timer = timers.first(where: { $0.delay == delay }) else { return }
      timers.removeAll { $0.id == timer.id }
      timer.fire()
    }
  }

  private let quiet = Duration.milliseconds(500)
  private let longest = Duration.seconds(1)

  private struct Rig {
    let saver: StateSaver
    let store: MemoryStore
    let clock: ManualClock
    let box: Box
  }

  final class Box {
    var enabled = true
    var location = "file:///a/"
  }

  private func rig(enabled: Bool = true) -> Rig {
    let store = MemoryStore()
    let clock = ManualClock()
    let box = Box()
    box.enabled = enabled
    let saver = StateSaver(
      store: store, isEnabled: { box.enabled },
      capture: { [box] in
        SavedState(windows: [SavedWindow(tabs: [SavedTab(location: box.location)])])
      },
      quiet: quiet, longest: longest, schedule: clock.scheduler)
    return Rig(saver: saver, store: store, clock: clock, box: box)
  }

  @Test func threeChangesInsideTheDelayMakeOneWrite() {
    let rig = rig()
    rig.saver.noteChange()
    rig.saver.noteChange()
    rig.saver.noteChange()
    #expect(rig.store.saves == 0)
    rig.clock.fire(quiet)
    #expect(rig.store.saves == 1)
    #expect(!rig.saver.hasPendingChange)
    #expect(rig.clock.timers.isEmpty)
  }

  @Test func changesThatNeverPauseStillWriteWithinTheMaxWait() {
    let rig = rig()
    for _ in 0..<5 {
      rig.saver.noteChange()  // each restarts the quiet timer
    }
    #expect(rig.clock.timers.filter { $0.delay == quiet }.count == 1)
    rig.clock.fire(longest)
    #expect(rig.store.saves == 1)
    #expect(rig.clock.timers.isEmpty)
  }

  @Test func theMaxWaitRestartsAfterAWrite() {
    let rig = rig()
    rig.saver.noteChange()
    rig.clock.fire(quiet)
    rig.box.location = "file:///b/"
    rig.saver.noteChange()
    #expect(rig.clock.timers.contains { $0.delay == longest })
    rig.clock.fire(longest)
    #expect(rig.store.saves == 2)
  }

  @Test func flushWritesAtOnceAndOnlyWhenSomethingWaits() {
    let rig = rig()
    rig.saver.flush()
    #expect(rig.store.saves == 0)
    rig.saver.noteChange()
    rig.saver.flush()
    #expect(rig.store.saves == 1)
    #expect(rig.clock.timers.isEmpty)
  }

  @Test func aWriteHappensWithNoQuit() throws {
    let rig = rig()
    rig.saver.noteChange()
    rig.clock.fire(quiet)
    let data = try #require(rig.store.data)
    #expect(SavedState.decode(data)?.windows.first?.tabs.first?.location == "file:///a/")
  }

  @Test func identicalStateIsNotWrittenAgain() {
    let rig = rig()
    rig.saver.noteChange()
    rig.clock.fire(quiet)
    rig.saver.noteChange()
    rig.clock.fire(quiet)
    #expect(rig.store.saves == 1)
  }

  @Test func nothingIsWrittenWhenRestorationIsOff() {
    let rig = rig(enabled: false)
    rig.saver.noteChange()
    rig.saver.flush()
    #expect(rig.clock.timers.isEmpty)
    #expect(rig.store.saves == 0)
  }

  @Test func turningRestorationOffClearsTheBlobAndStopsTimers() {
    let rig = rig()
    rig.saver.noteChange()
    rig.clock.fire(quiet)
    rig.saver.noteChange()
    rig.box.enabled = false
    rig.saver.settingChanged()
    #expect(rig.store.data == nil)
    #expect(rig.clock.timers.isEmpty)
    // Back on: the current state is saved again.
    rig.box.enabled = true
    rig.saver.settingChanged()
    rig.clock.fire(quiet)
    #expect(rig.store.data != nil)
  }

  @Test func aClosedWindowIsForgottenAndNothingMoreIsSaved() {
    let rig = rig()
    rig.saver.noteChange()
    rig.clock.fire(quiet)
    #expect(rig.store.data != nil)
    rig.saver.noteChange()
    rig.saver.windowClosed()
    #expect(rig.store.data == nil)
    #expect(rig.clock.timers.isEmpty)
    rig.saver.noteChange()
    rig.saver.flush()
    #expect(rig.store.data == nil)
  }

  @Test func theSettingDefaultsToOn() throws {
    let name = "StateSaverTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = BrowserSettings(defaults: defaults)
    #expect(settings.restoresWindows)
    settings.restoresWindows = false
    #expect(!BrowserSettings(defaults: defaults).restoresWindows)
    #expect(defaults.bool(forKey: BrowserSettings.restoresWindowsKey) == false)
  }
}
