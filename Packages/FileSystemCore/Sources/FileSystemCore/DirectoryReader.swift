import Foundation

/// What a listing hands over while a folder is read.
public enum DirectoryListingEvent: Sendable, Equatable {
  /// The first items of a folder that holds more than one batch, in the order
  /// they were read. Sent at most once, before ``allItems(_:)``.
  case firstItems([FileItem])
  /// Every item directly inside the folder, the first items included. Always
  /// the last event.
  case allItems([FileItem])
}

/// Lists the contents of a folder. The protocol exists so tests can supply
/// slow or failing listings.
public protocol DirectoryReading: Sendable {
  /// Every item directly inside `directory`, hidden items included, in no
  /// particular order, as at most two events. A listing with no
  /// ``DirectoryListingEvent/firstItems(_:)`` event fit in one batch.
  ///
  /// The folder is read off the caller's actor, so the stream is safe to
  /// consume from the main actor. A failed listing ends the stream with its
  /// error. When the consuming task is cancelled the stream ends without
  /// throwing and the listing stops.
  func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error>
}

extension DirectoryReading {
  /// Every item directly inside `directory`, for a caller that does not want
  /// the first items early: ``listing(in:)`` read to its end.
  ///
  /// Never runs on the caller's actor, so it is safe to await from the main
  /// actor. Throws `CancellationError` if the task is cancelled.
  public func items(in directory: URL) async throws -> [FileItem] {
    try Task.checkCancellation()
    var all: [FileItem]?
    for try await event in listing(in: directory) {
      if case .allItems(let items) = event {
        all = items
      }
    }
    // A cancelled stream ends without throwing.
    try Task.checkCancellation()
    guard let all else { throw DirectoryReadError.incomplete(directory) }
    return all
  }
}

/// Why a folder could not be listed.
public enum DirectoryReadError: Error, Equatable, Sendable {
  case notADirectory(URL)
  /// The listing ended before it had handed over every item.
  case incomplete(URL)
}

extension DirectoryReadError: LocalizedError {
  /// Shown in the browser in place of the listing.
  public var errorDescription: String? {
    switch self {
    case .notADirectory(let url): "\(url.lastPathComponent) is not a folder."
    case .incomplete(let url): "The contents of \(url.lastPathComponent) could not be read."
    }
  }
}

/// Lists folders on disk, prefetching the resource keys a listing shows.
public struct DirectoryReader: DirectoryReading {
  /// How many items are read between cancellation checks.
  static let cancellationInterval = 256
  /// How many items a folder's first batch holds. A folder with more than
  /// this many hands its first batch over before the rest has been read.
  static let firstBatchSize = 2_000

  public init() {}

  public func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
    Self.listing(in: directory)
  }

  /// - Parameter onCancellationCheck: Passed on to
  ///   ``readItems(in:onCancellationCheck:onFirstItems:)``.
  static func listing(
    in directory: URL,
    onCancellationCheck: @escaping @Sendable (_ itemsRead: Int) -> Void = { _ in }
  ) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
    let (stream, continuation) = AsyncThrowingStream<DirectoryListingEvent, any Error>.makeStream()
    // This function is not isolated, so the task leaves the caller's actor. It
    // keeps the caller's priority and task-local values.
    let task = Task {
      do {
        let items = try readItems(in: directory, onCancellationCheck: onCancellationCheck) {
          continuation.yield(.firstItems($0))
        }
        continuation.yield(.allItems(items))
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    // The stream ends from the consumer's side when its task is cancelled or
    // it stops reading. Either way the listing has no one left to read it.
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  /// Synchronous because `FileManager`'s enumerator cannot be iterated from
  /// an async context. Call it only from ``listing(in:onCancellationCheck:)``.
  /// - Parameter onCancellationCheck: Called with the number of items read so
  ///   far, just before each cancellation check. Tests use it to cancel a
  ///   listing that is under way.
  /// - Parameter onFirstItems: Called once with the first
  ///   ``firstBatchSize`` items, when the item after them has been read. Not
  ///   called for a folder that has no such item.
  static func readItems(
    in directory: URL, onCancellationCheck: (_ itemsRead: Int) -> Void = { _ in },
    onFirstItems: (_ items: [FileItem]) -> Void = { _ in }
  ) throws -> [FileItem] {
    MainThreadGuard.assertOffMainThread()
    let started = ContinuousClock.now
    // The location may itself be a symbolic link, as /tmp and /var are. Neither
    // the directory check nor the enumerator follows one, so follow it here.
    // The items are then reported under the folder the link leads to.
    let target = followingSymbolicLinks(directory)
    let isDirectory = try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    guard isDirectory == true else {
      throw DirectoryReadError.notADirectory(directory)
    }

    var failure: (any Error)?
    let enumerator = FileManager.default.enumerator(
      at: target,
      includingPropertiesForKeys: Array(FileItem.resourceKeys),
      options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants],
      errorHandler: { _, error in
        failure = error
        return false
      }
    )
    guard let enumerator else {
      throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: directory])
    }

    var items: [FileItem] = []
    for case let url as URL in enumerator {
      if items.count.isMultiple(of: cancellationInterval) {
        onCancellationCheck(items.count)
        try Task.checkCancellation()
      }
      // An item deleted since it was listed has no values; leave it out.
      guard let values = try? url.resourceValues(forKeys: FileItem.resourceKeys) else { continue }
      if items.count == firstBatchSize {
        onFirstItems(items)
      }
      items.append(FileItem(url: url, resourceValues: values))
    }
    if let failure {
      Log.fileSystem.error(
        "Listing failed after \(items.count) items: \(failure.localizedDescription)")
      throw failure
    }
    let elapsed = ContinuousClock.now - started
    Log.fileSystem.debug("Listed \(items.count) items in \(elapsed, privacy: .public)")
    return items
  }

  /// The location with every symbolic link in its path followed. A location
  /// that cannot be resolved (a missing folder, say) is returned unchanged,
  /// and listing it reports why.
  private static func followingSymbolicLinks(_ location: URL) -> URL {
    guard let path = realpath(location.path(percentEncoded: false), nil) else { return location }
    defer { free(path) }
    return URL(fileURLWithFileSystemRepresentation: path, isDirectory: false, relativeTo: nil)
  }
}
