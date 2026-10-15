import Foundation

/// Finds the files a virtual location stands for. The protocol exists so
/// tests supply results without Spotlight.
public protocol VirtualLocationSearching: Sendable {
  /// The files at `location`, most relevant first, at most `limit`.
  func files(at location: VirtualLocation, limit: Int) async throws -> [URL]
}

/// Spotlight, local to this Mac.
public struct SpotlightSearcher: VirtualLocationSearching {
  /// How many days back Recents goes.
  static let recentDays = 7

  /// Restricts the search to this folder. Nil searches this Mac.
  private let scope: URL?

  public init(scope: URL? = nil) {
    self.scope = scope
  }

  /// The searcher for this launch: this Mac, or the folder the `SearchScope`
  /// launch argument names. End-to-end tests name their fixture folder, so
  /// what they list is theirs and not whatever the person used lately.
  public static func forThisLaunch() -> SpotlightSearcher {
    guard let path = UserDefaults.standard.string(forKey: "SearchScope"), !path.isEmpty else {
      return SpotlightSearcher()
    }
    return SpotlightSearcher(scope: URL(filePath: path, directoryHint: .isDirectory))
  }

  public func files(at location: VirtualLocation, limit: Int) async throws -> [URL] {
    let predicate: NSPredicate
    let sort: [NSSortDescriptor]
    switch location {
    case .tag(let name):
      predicate = NSPredicate(format: "kMDItemUserTags == %@", name)
      sort = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
    case .recents:
      let since = Date().addingTimeInterval(-Double(Self.recentDays) * 86_400)
      predicate = NSPredicate(format: "%K >= %@", NSMetadataItemLastUsedDateKey, since as NSDate)
      sort = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
    }
    return await MetadataQuery.paths(
      predicate: predicate, sortedBy: sort, limit: limit, scope: scope
    )
    .map { URL(filePath: $0) }
  }
}

/// Lists a virtual location (a tag, the recents) with the same events a
/// folder listing has, so the model's load, sort and refresh need no second
/// path.
public struct MetadataQueryReader: DirectoryReading {
  /// The most items a virtual listing holds.
  public static let limit = 1_000

  private let searcher: any VirtualLocationSearching

  public init(searcher: any VirtualLocationSearching = SpotlightSearcher.forThisLaunch()) {
    self.searcher = searcher
  }

  public func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
    let searcher = searcher
    return AsyncThrowingStream { continuation in
      let task = Task {
        guard let location = VirtualLocation(url: directory) else {
          continuation.finish(throwing: DirectoryReadError.notADirectory(directory))
          return
        }
        do {
          let urls = try await searcher.files(at: location, limit: Self.limit)
          try Task.checkCancellation()
          let items = Self.items(for: urls)
          continuation.yield(.allItems(items))
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// An item for each file that is still there. A result the index has not
  /// forgotten yet, for a file that was deleted, is left out.
  static func items(for urls: [URL]) -> [FileItem] {
    MainThreadGuard.assertOffMainThread()
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: FileItem.resourceKeys) else {
        return nil
      }
      return FileItem(url: url, resourceValues: values)
    }
  }
}

/// Sends a listing to the reader that answers its kind of location: a folder
/// to the folder reader, a virtual location to the query reader.
public struct CompositeReader: DirectoryReading {
  private let files: any DirectoryReading
  private let virtual: any DirectoryReading

  public init(
    files: any DirectoryReading = DirectoryReader(),
    virtual: any DirectoryReading = MetadataQueryReader()
  ) {
    self.files = files
    self.virtual = virtual
  }

  public func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
    VirtualLocation.isVirtual(directory)
      ? virtual.listing(in: directory) : files.listing(in: directory)
  }
}
