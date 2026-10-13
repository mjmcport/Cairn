import Foundation

/// The mounted volumes, as the system reports them.
public protocol VolumeSource: Sendable {
  /// The visible volumes, startup disk first. Touches the file system.
  func volumes() -> [VolumeInfo]
}

/// The folders cloud services keep on this Mac.
public protocol CloudSource: Sendable {
  func folders() -> [CloudFolder]
}

/// The tags that are in use.
public protocol TagSource: Sendable {
  func tags() async -> [TagInfo]
}

/// Volumes from `FileManager`.
public struct SystemVolumeSource: VolumeSource {
  public init() {}

  public func volumes() -> [VolumeInfo] {
    MainThreadGuard.assertOffMainThread()
    let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
    guard
      let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes])
    else { return [] }
    return urls.map { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      let ejectable = (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false)
      return VolumeInfo(
        url: url, name: values?.volumeName ?? url.lastPathComponent, isEjectable: ejectable)
    }
  }
}

/// iCloud Drive, and each folder under `~/Library/CloudStorage`.
public struct SystemCloudSource: CloudSource {
  private let home: URL

  public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.home = home
  }

  public func folders() -> [CloudFolder] {
    MainThreadGuard.assertOffMainThread()
    let manager = FileManager.default
    var found: [CloudFolder] = []

    let iCloud = home.appending(
      path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: iCloud.path, isDirectory: &isDirectory), isDirectory.boolValue {
      found.append(CloudFolder(url: iCloud, name: "iCloud Drive", isICloudDrive: true))
    }

    let storage = home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
    let entries =
      (try? manager.contentsOfDirectory(
        at: storage, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])) ?? []
    for entry in entries {
      guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        continue
      }
      found.append(CloudFolder(url: entry, name: Self.displayName(of: entry.lastPathComponent)))
    }
    return found
  }

  /// A service's folder is named `Provider-Account`; the sidebar says the
  /// provider and the account the way the folder does, with the dash spaced.
  static func displayName(of folderName: String) -> String {
    folderName.replacingOccurrences(of: "-", with: " – ")
  }
}

/// Tags in use, from a metadata query's list of the values of the tag
/// attribute.
public struct SpotlightTagSource: TagSource {
  private let scope: URL?

  /// Searches this Mac, or the folder the `SearchScope` launch argument
  /// names (see ``SpotlightSearcher/forThisLaunch()``).
  public init(
    scope: URL? = UserDefaults.standard.string(forKey: "SearchScope").flatMap {
      $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory)
    }
  ) {
    self.scope = scope
  }

  public func tags() async -> [TagInfo] {
    await MetadataQuery.valueList(
      predicate: NSPredicate(format: "kMDItemUserTags LIKE '*'"), attribute: "kMDItemUserTags",
      scope: scope
    ).map { TagInfo(name: $0.value, count: $0.count) }
  }
}
