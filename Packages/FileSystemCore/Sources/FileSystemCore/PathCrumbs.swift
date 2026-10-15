import Foundation

/// One name of the path bar: a folder from the root down to the one showing.
public struct Crumb: Sendable, Equatable {
  public let title: String
  public let url: URL
  /// True for the last crumb, the place being shown.
  public let isCurrent: Bool

  public init(title: String, url: URL, isCurrent: Bool) {
    self.title = title
    self.url = url
    self.isCurrent = isCurrent
  }
}

/// Turns a location into the names the path bar shows. Pure: it makes no
/// file-system call, so it can run anywhere.
public enum PathCrumbs {
  /// What the root folder is called when the caller does not know the name of
  /// the startup volume.
  public static let defaultRootName = "Macintosh HD"

  /// The crumbs of `location`, root first. A virtual location is one crumb
  /// that names the place, since it has no folders above it.
  public static func crumbs(for location: URL, rootName: String = defaultRootName) -> [Crumb] {
    if let virtual = VirtualLocation(url: location) {
      return [Crumb(title: virtual.title, url: location, isCurrent: true)]
    }
    var urls: [URL] = []
    var url = URL(filePath: location.path(percentEncoded: false), directoryHint: .isDirectory)
      .standardizedFileURL
    while true {
      urls.append(url)
      let parent = url.deletingLastPathComponent()
      if parent.path(percentEncoded: false) == url.path(percentEncoded: false) { break }
      url = parent
    }
    urls.reverse()
    return urls.enumerated().map { index, url in
      let isRoot = index == 0
      let title = isRoot ? rootName : url.lastPathComponent
      return Crumb(title: title, url: url, isCurrent: index == urls.count - 1)
    }
  }
}

extension PathCrumbs {
  /// The name of the startup volume, read off the main thread. Nil when the
  /// system does not say.
  public static func startupVolumeName() -> String? {
    MainThreadGuard.assertOffMainThread()
    let values = try? URL(filePath: "/").resourceValues(forKeys: [.volumeNameKey])
    return values?.volumeName
  }
}
