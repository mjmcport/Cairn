import Foundation

/// One-shot Spotlight queries, local to this Mac. Nothing here touches the
/// network: the search scope is the local computer.
enum MetadataQuery {
  /// A value of an attribute and how many results carry it.
  struct ValueCount: Sendable, Equatable {
    let value: String
    let count: Int
  }

  /// Runs one query to the end of its first gathering and hands the result
  /// to a continuation exactly once: from the finished notification, or from
  /// the timeout, whichever comes first.
  ///
  /// `NSMetadataQuery` is not `Sendable`. The runner owns it, results are
  /// read on the operation queue the notification arrives on, and `lock`
  /// serializes the one hand-over.
  private final class Run<Value: Sendable>: @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<Value, Never>?
    private let timeoutValue: Value

    init(timeoutValue: Value) {
      self.timeoutValue = timeoutValue
    }

    func run(
      predicate: NSPredicate, sortedBy sort: [NSSortDescriptor] = [],
      valueListAttributes: [String] = [], scope: URL?, timeout: TimeInterval,
      read: @escaping @Sendable (NSMetadataQuery) -> Value
    ) async -> Value {
      await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        query.predicate = predicate
        query.sortDescriptors = sort
        query.valueListAttributes = valueListAttributes
        query.searchScopes =
          scope.map { [$0.path] } ?? [NSMetadataQueryLocalComputerScope]
        // Results arrive on this queue, not on the main run loop.
        query.operationQueue = OperationQueue()
        observer = NotificationCenter.default.addObserver(
          forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil
        ) { [self] _ in
          finish { read(query) }
        }
        query.start()

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
          finish { timeoutValue }
        }
      }
    }

    private func finish(_ value: () -> Value) {
      lock.lock()
      guard let continuation else {
        lock.unlock()
        return
      }
      self.continuation = nil
      lock.unlock()

      query.disableUpdates()
      let result = value()
      query.stop()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      continuation.resume(returning: result)
    }
  }

  /// The values `attribute` takes among the results of `predicate`, with how
  /// many results carry each. Empty when the query does not finish in
  /// `timeout` seconds.
  static func valueList(
    predicate: NSPredicate, attribute: String, scope: URL? = nil, timeout: TimeInterval = 10
  ) async -> [ValueCount] {
    await Run<[ValueCount]>(timeoutValue: []).run(
      predicate: predicate, valueListAttributes: [attribute], scope: scope, timeout: timeout
    ) { query in
      (query.valueLists[attribute] ?? []).compactMap { tuple in
        guard let value = tuple.value as? String else { return nil }
        return ValueCount(value: value, count: tuple.count)
      }
    }
  }

  /// The paths of the results of `predicate`, in `sortedBy` order, at most
  /// `limit`. Empty when the query does not finish in `timeout` seconds.
  static func paths(
    predicate: NSPredicate, sortedBy sort: [NSSortDescriptor], limit: Int, scope: URL? = nil,
    timeout: TimeInterval = 10
  ) async -> [String] {
    await Run<[String]>(timeoutValue: []).run(
      predicate: predicate, sortedBy: sort, scope: scope, timeout: timeout
    ) { query in
      var found: [String] = []
      for index in 0..<min(query.resultCount, limit) {
        guard let item = query.result(at: index) as? NSMetadataItem,
          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
        else { continue }
        found.append(path)
      }
      return found
    }
  }
}
