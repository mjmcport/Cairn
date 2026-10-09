import FileSystemCore
import Foundation

/// A listing that returns canned items and can be held at a gate.
struct StubReader: DirectoryReading {
  var results: [URL: [FileItem]]
  var gates: [URL: Gate] = [:]

  func items(in directory: URL) async throws -> [FileItem] {
    if let gate = gates[directory] {
      await gate.pass()
    }
    try Task.checkCancellation()
    guard let items = results[directory] else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return items
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
}
