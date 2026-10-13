import Foundation

/// One favorite as it is kept: bookmark data, so the favorite follows the
/// folder when it is moved or renamed, and the name it had.
public struct FavoriteRecord: Codable, Sendable, Equatable {
  public var id: String
  public var bookmark: Data
  public var name: String

  public init(id: String = UUID().uuidString, bookmark: Data, name: String) {
    self.id = id
    self.bookmark = bookmark
    self.name = name
  }
}

/// A favorite after its bookmark was resolved. `url` is nil when the folder
/// could not be found; the favorite is kept, and shown as missing.
public struct ResolvedFavorite: Sendable, Equatable {
  public let id: String
  public let name: String
  public let url: URL?

  public init(id: String, name: String, url: URL?) {
    self.id = id
    self.name = name
    self.url = url
  }
}

/// Where favorites are kept.
public protocol FavoriteStoring: Sendable {
  /// The favorites that were saved, or nil when none ever were, which means
  /// the defaults.
  func load() -> [FavoriteRecord]?
  func save(_ records: [FavoriteRecord])
}

/// Favorites kept as JSON in the user defaults.
public struct UserDefaultsFavoriteStore: FavoriteStoring, @unchecked Sendable {
  public static let key = "SidebarFavorites"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The store for this launch: the standard defaults, or the suite the
  /// `FavoritesSuite` launch argument names. End-to-end tests name a suite of
  /// their own, so they never read or change the person's favorites.
  public static func forThisLaunch() -> UserDefaultsFavoriteStore {
    if let name = UserDefaults.standard.string(forKey: "FavoritesSuite"), !name.isEmpty,
      let suite = UserDefaults(suiteName: name)
    {
      return UserDefaultsFavoriteStore(defaults: suite)
    }
    return UserDefaultsFavoriteStore()
  }

  public func load() -> [FavoriteRecord]? {
    guard let data = defaults.data(forKey: Self.key) else { return nil }
    return try? JSONDecoder().decode([FavoriteRecord].self, from: data)
  }

  public func save(_ records: [FavoriteRecord]) {
    defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
  }
}

/// Making, resolving and defaulting favorites. Every function touches the
/// file system and so starts with the main-thread guard.
public enum Favorites {
  /// A favorite for `folder`.
  public static func record(for folder: URL, named name: String? = nil) throws -> FavoriteRecord {
    MainThreadGuard.assertOffMainThread()
    let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil)
    return FavoriteRecord(bookmark: bookmark, name: name ?? folder.lastPathComponent)
  }

  /// Resolves each bookmark. A bookmark that cannot be resolved, or whose
  /// folder is gone, is kept with no URL.
  public static func resolve(_ records: [FavoriteRecord]) -> [ResolvedFavorite] {
    MainThreadGuard.assertOffMainThread()
    return records.map { record in
      var stale = false
      let url = try? URL(
        resolvingBookmarkData: record.bookmark, options: [.withoutUI, .withoutMounting],
        relativeTo: nil, bookmarkDataIsStale: &stale)
      let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
      return ResolvedFavorite(id: record.id, name: record.name, url: exists ? url : nil)
    }
  }

  /// Home, Desktop, Documents, Downloads and Applications, where they exist.
  public static func defaults() -> [FavoriteRecord] {
    MainThreadGuard.assertOffMainThread()
    let manager = FileManager.default
    var folders: [(URL, String)] = [(manager.homeDirectoryForCurrentUser, "Home")]
    for (directory, name) in [
      (FileManager.SearchPathDirectory.desktopDirectory, "Desktop"),
      (.documentDirectory, "Documents"),
      (.downloadsDirectory, "Downloads"),
      (.applicationDirectory, "Applications"),
    ] {
      if let url = manager.urls(for: directory, in: .userDomainMask).first
        ?? manager.urls(for: directory, in: .localDomainMask).first
      {
        folders.append((url, name))
      }
    }
    return folders.compactMap { url, name in
      var isDirectory: ObjCBool = false
      guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
      else { return nil }
      return try? record(for: url, named: name)
    }
  }
}
