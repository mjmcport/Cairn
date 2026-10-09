import Foundation

/// Lists the contents of a folder. The protocol exists so tests can supply
/// slow or failing listings.
public protocol DirectoryReading: Sendable {
  /// Every item directly inside `directory`, hidden items included, in no
  /// particular order.
  ///
  /// Never runs on the caller's actor, so it is safe to await from the main
  /// actor. Throws `CancellationError` if the task is cancelled.
  func items(in directory: URL) async throws -> [FileItem]
}

/// Why a folder could not be listed.
public enum DirectoryReadError: Error, Equatable, Sendable {
  case notADirectory(URL)
}

/// Lists folders on disk, prefetching the resource keys a listing shows.
public struct DirectoryReader: DirectoryReading {
  /// How many items are read between cancellation checks.
  static let cancellationInterval = 256

  public init() {}

  public func items(in directory: URL) async throws -> [FileItem] {
    try Task.checkCancellation()
    return try Self.readItems(in: directory)
  }

  /// Synchronous because `FileManager`'s enumerator cannot be iterated from
  /// an async context. Call it only from ``items(in:)``.
  static func readItems(in directory: URL) throws -> [FileItem] {
    MainThreadGuard.assertOffMainThread()
    let started = ContinuousClock.now
    let isDirectory = try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    guard isDirectory == true else {
      throw DirectoryReadError.notADirectory(directory)
    }

    var failure: (any Error)?
    let enumerator = FileManager.default.enumerator(
      at: directory,
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
        try Task.checkCancellation()
      }
      // An item deleted since it was listed has no values; leave it out.
      guard let values = try? url.resourceValues(forKeys: FileItem.resourceKeys) else { continue }
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
}
