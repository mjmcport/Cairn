import Foundation

/// Writes the window's saved state a moment after something in it changes,
/// not at quit, so a crash loses at most that moment. Quit flushes at once.
///
/// Changes are collected: each one restarts a short quiet timer, and the
/// first one after a write also starts a longer one that is never restarted,
/// so a drag that never pauses still saves. Whichever fires first writes.
/// A write that would store the bytes already stored is skipped.
///
/// Saving writes the user defaults, which the system caches; no file is
/// touched on the main thread.
@MainActor
public final class StateSaver {
  /// Starts a timer and returns what cancels it. Tests replace it with a
  /// scheduler they fire by hand.
  public typealias Scheduler =
    @MainActor (_ after: Duration, _ fire: @escaping @MainActor () -> Void) -> () -> Void

  public static let quietDelay = Duration.milliseconds(500)
  public static let maxWait = Duration.seconds(1)

  /// The scheduler used outside tests: a task that sleeps.
  public static let taskScheduler: Scheduler = { delay, fire in
    let task = Task { @MainActor in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      fire()
    }
    return { task.cancel() }
  }

  private let store: any StateStoring
  private let isEnabled: @MainActor () -> Bool
  private let capture: @MainActor () -> SavedState?
  private let schedule: Scheduler
  private let quiet: Duration
  private let longest: Duration

  private var cancelQuiet: (() -> Void)?
  private var cancelLongest: (() -> Void)?
  private var lastWritten: Data?
  /// Set when the person closed the window: what it showed is not kept.
  private var isClosed = false
  /// How many times the store was written. For tests.
  public private(set) var writeCount = 0

  /// - Parameter isEnabled: Whether restoration is on (R16). Asked at each
  ///   change, so turning the setting off stops saving.
  /// - Parameter capture: The state to save now, or nil when there is none.
  public init(
    store: any StateStoring, isEnabled: @escaping @MainActor () -> Bool,
    capture: @escaping @MainActor () -> SavedState?,
    quiet: Duration = StateSaver.quietDelay, longest: Duration = StateSaver.maxWait,
    schedule: @escaping Scheduler = StateSaver.taskScheduler
  ) {
    self.store = store
    self.isEnabled = isEnabled
    self.capture = capture
    self.quiet = quiet
    self.longest = longest
    self.schedule = schedule
    lastWritten = store.load()
  }

  /// Whether a change is waiting to be written.
  public var hasPendingChange: Bool { cancelLongest != nil }

  /// Something in the saved state may have changed.
  public func noteChange() {
    guard isEnabled(), !isClosed else { return }
    cancelQuiet?()
    cancelQuiet = schedule(quiet) { [weak self] in self?.write() }
    if cancelLongest == nil {
      cancelLongest = schedule(longest) { [weak self] in self?.write() }
    }
  }

  /// Writes a waiting change now. Called at quit.
  public func flush() {
    guard hasPendingChange else { return }
    write()
  }

  /// The restoration setting changed. Off: nothing waits and the saved blob
  /// is removed, so a later launch with it on does not bring back old
  /// windows. On: the current state is saved.
  public func settingChanged() {
    if isEnabled() {
      noteChange()
    } else {
      stopTimers()
      store.clear()
      lastWritten = nil
    }
  }

  /// The person closed the window: a later launch starts fresh, and nothing
  /// more is saved.
  public func windowClosed() {
    isClosed = true
    stopTimers()
    store.clear()
    lastWritten = nil
  }

  private func stopTimers() {
    cancelQuiet?()
    cancelLongest?()
    cancelQuiet = nil
    cancelLongest = nil
  }

  private func write() {
    stopTimers()
    guard isEnabled(), !isClosed, let state = capture(), let data = state.encoded() else { return }
    guard data != lastWritten else { return }
    store.save(data)
    lastWritten = data
    writeCount += 1
  }
}
