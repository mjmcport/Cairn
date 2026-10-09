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

extension DirectoryReadError: LocalizedError {
  /// Shown in the browser in place of the listing.
  public var errorDescription: String? {
    switch self {
    case .notADirectory(let url): "\(url.lastPathComponent) is not a folder."
    }
  }
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
  /// - Parameter onCancellationCheck: Called with the number of items read so
  ///   far, just before each cancellation check. Tests use it to cancel a
  ///   listing that is under way.
  static func readItems(
    in directory: URL, onCancellationCheck: (_ itemsRead: Int) -> Void = { _ in }
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
