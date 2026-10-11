import FileSystemCore
import Foundation

/// A listing that returns canned items and can be held at a gate.
struct StubReader: DirectoryReading {
  var results: [URL: [FileItem]]
  var gates: [URL: Gate] = [:]
  /// Folders that hand these items over first, as a folder larger than one
  /// batch does. Without `results` for it, such a folder fails after them.
  var firstItems: [URL: [FileItem]] = [:]
  /// Held between a folder's first items and what follows them. The gate is
  /// reached when the consumer has taken the first items and asked for more.
  var gatesAfterFirstItems: [URL: Gate] = [:]
  /// Folders whose listing ends after the first items, with no error.
  var endingEarly: Set<URL> = []
  /// The folders whose listing found its consumer cancelled and stopped.
  let cancelledListings = Recorded<[URL]>([])

  func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
    let asked = Counter()
    // The stream asks for each event as its consumer does, so a gate holds
    // the consumer where the test expects it.
    return AsyncThrowingStream {
      let first = firstItems[directory]
      switch asked.next() {
      case 0:
        if let gate = gates[directory] {
          await gate.pass()
        }
        guard !stopsIfCancelled(directory) else { return nil }
        if let first {
          return .firstItems(first)
        }
      case 1 where first != nil:
        if let gate = gatesAfterFirstItems[directory] {
          await gate.pass()
        }
        guard !stopsIfCancelled(directory), !endingEarly.contains(directory) else { return nil }
      default:
        return nil
      }
      guard let items = results[directory] else {
        throw CocoaError(.fileReadNoSuchFile)
      }
      return .allItems(items)
    }
  }

  /// Like the real stream, a listing whose consumer was cancelled ends
  /// without throwing.
  private func stopsIfCancelled(_ directory: URL) -> Bool {
    guard Task.isCancelled else { return false }
    cancelledListings.value += [directory]
    return true
  }
}

/// Counts calls, from any thread.
final class Counter: @unchecked Sendable {
  // Guarded by `lock`.
  private var count = 0
  private let lock = NSLock()

  /// How many calls came before this one.
  func next() -> Int {
    lock.withLock {
      defer { count += 1 }
      return count
    }
  }
}

/// A value written and read from any thread.
final class Recorded<Value: Sendable>: @unchecked Sendable {
  // Guarded by `lock`.
  private var stored: Value
  private let lock = NSLock()

  init(_ value: Value) { stored = value }

  var value: Value {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

/// Holds a caller at `pass()` until `open()` is called.
actor Gate {
  private var isOpen = false
  private var reached = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var reachedWaiters: [CheckedContinuation<Void, Never>] = []

  func pass() async {
    reached = true
    for waiter in reachedWaiters { waiter.resume() }
    reachedWaiters = []
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilReached() async {
    guard !reached else { return }
    await withCheckedContinuation { reachedWaiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }

  /// Makes the gate hold again, for a test that passes it twice.
  func close() {
    isOpen = false
    reached = false
  }
}
