import FileSystemCore
import Foundation

@testable import BrowserUI

/// A watcher whose signals a test sends by hand. It records which folders
/// were asked for and lets a test wait for a folder's stream to end, which
/// is what stops a real watch.
///
/// Unlike the real watcher it sends no `live` signal unless asked to, and it
/// keeps every signal: what a model does with several is the model's doing.
final class StubWatcher: FolderWatching, @unchecked Sendable {
  private typealias Waiter = CheckedContinuation<Void, Never>

  // Guarded by `lock`.
  private var feeds: [Feed] = []
  private var endWaiters: [(folder: URL, count: Int, continuation: Waiter)] = []
  private let lock = NSLock()
  /// Whether every stream ends as soon as it is asked for, like a watch that
  /// could not start.
  private let endsAtOnce: Bool
  /// Whether every stream begins with `live`, as a real watch does.
  private let sendsLive: Bool

  init(endsAtOnce: Bool = false, sendsLive: Bool = false) {
    self.endsAtOnce = endsAtOnce
    self.sendsLive = sendsLive
  }

  func signals(for folder: URL) -> AsyncStream<FolderChangeSignal> {
    let feed = Feed(folder: folder, queued: sendsLive ? [.live] : []) { [weak self] in
      self?.aStreamEnded()
    }
    lock.withLock { feeds.append(feed) }
    if endsAtOnce {
      feed.end()
    }
    // The stream asks for each signal as its consumer does, so the feed
    // knows when the consumer has finished with the one before.
    return AsyncStream(unfolding: { await feed.next() }, onCancel: { feed.end() })
  }

  private func aStreamEnded() {
    let ready = lock.withLock {
      let ended = endedCounts
      let ready = endWaiters.filter { ended[$0.folder, default: 0] >= $0.count }
      endWaiters.removeAll { ended[$0.folder, default: 0] >= $0.count }
      return ready
    }
    for waiter in ready { waiter.continuation.resume() }
  }

  /// How many streams of each folder have ended. Call with `lock` held.
  private var endedCounts: [URL: Int] {
    feeds.filter(\.hasEnded).reduce(into: [:]) { $0[$1.folder, default: 0] += 1 }
  }

  /// Every folder whose signals were asked for, in order, ended or not.
  var requested: [URL] { lock.withLock { feeds.map(\.folder) } }

  /// The folders with a stream that has not ended: what is being watched.
  var watched: [URL] { lock.withLock { feeds.filter { !$0.hasEnded }.map(\.folder) } }

  /// Sends a signal on the newest stream of `folder`, as FSEvents would, and
  /// returns once the consumer has taken it and come back for the next: by
  /// then a model has heard the signal. A signal for a stream that has ended
  /// goes nowhere, as it does for real.
  func send(_ signal: FolderChangeSignal = .contentsChanged, to folder: URL) async {
    let feed = lock.withLock { feeds.last { $0.folder == folder } }
    await feed?.send(signal)
  }

  /// Waits until `count` streams of `folder` have ended.
  func waitForEnd(of folder: URL, count: Int = 1) async {
    await withCheckedContinuation { continuation in
      let hasEnded = lock.withLock {
        if endedCounts[folder, default: 0] >= count { return true }
        endWaiters.append((folder, count, continuation))
        return false
      }
      if hasEnded { continuation.resume() }
    }
  }
}

/// The signals of one stream, handed over one at a time as the consumer asks.
private final class Feed: @unchecked Sendable {
  private typealias Consumer = CheckedContinuation<FolderChangeSignal?, Never>
  private typealias Sender = CheckedContinuation<Void, Never>
  /// What the consumer's ask is answered with at once, if anything.
  private enum Answer {
    case signal(FolderChangeSignal)
    case end
    case wait
  }

  let folder: URL
  private let onEnd: @Sendable () -> Void
  private let lock = NSLock()
  // Guarded by `lock`.
  private var queued: [FolderChangeSignal]
  /// How many times the consumer has asked for a signal.
  private var asks = 0
  private var waitingConsumer: Consumer?
  /// Senders waiting for the consumer's ask of that number.
  private var senders: [(ask: Int, continuation: Sender)] = []
  private var ended = false

  init(folder: URL, queued: [FolderChangeSignal], onEnd: @escaping @Sendable () -> Void) {
    self.folder = folder
    self.queued = queued
    self.onEnd = onEnd
  }

  var hasEnded: Bool { lock.withLock { ended } }

  func next() async -> FolderChangeSignal? {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (consumer: Consumer) in
        var heard: [Sender] = []
        let answer: Answer = lock.withLock {
          asks += 1
          heard = senders.filter { $0.ask <= asks }.map(\.continuation)
          senders.removeAll { $0.ask <= asks }
          if ended { return .end }
          if !queued.isEmpty { return .signal(queued.removeFirst()) }
          waitingConsumer = consumer
          return .wait
        }
        for sender in heard { sender.resume() }
        switch answer {
        case .signal(let signal): consumer.resume(returning: signal)
        case .end: consumer.resume(returning: nil)
        case .wait: break
        }
      }
    } onCancel: {
      end()
    }
  }

  func send(_ signal: FolderChangeSignal) async {
    await withCheckedContinuation { (sender: Sender) in
      var consumer: Consumer?
      let goesNowhere = lock.withLock {
        guard !ended else { return true }
        if let waiting = waitingConsumer {
          // Taken by the ask that is waiting; heard at the one after it.
          waitingConsumer = nil
          consumer = waiting
          senders.append((asks + 1, sender))
        } else {
          queued.append(signal)
          senders.append((asks + queued.count + 1, sender))
        }
        return false
      }
      consumer?.resume(returning: signal)
      if goesNowhere { sender.resume() }
    }
  }

  func end() {
    var consumer: Consumer?
    var waiting: [Sender] = []
    let isNews = lock.withLock {
      consumer = waitingConsumer
      waiting = senders.map(\.continuation)
      waitingConsumer = nil
      senders = []
      defer { ended = true }
      return !ended
    }
    consumer?.resume(returning: nil)
    for sender in waiting { sender.resume() }
    if isNews { onEnd() }
  }
}

/// Counts the times a model's watch session has finished with every signal
/// it had, so a test can wait for signals to be dealt with instead of
/// waiting on a clock.
@MainActor
final class AnsweredSignals {
  private(set) var count = 0
  private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  /// Installs itself as the model's hook. It does not hold the model.
  init(of model: BrowserModel) {
    model.onSignalsAnswered = { [self] in
      count += 1
      let ready = waiters.filter { $0.count <= count }
      waiters.removeAll { $0.count <= count }
      for waiter in ready { waiter.continuation.resume() }
    }
  }

  /// Waits until the session has gone quiet `count` times in all.
  func wait(for count: Int) async {
    guard self.count < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }
}
