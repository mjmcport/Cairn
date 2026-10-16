import FileSystemCore
import Foundation

/// Brings a saved tab back to a place that exists now (R14, R14a).
///
/// A folder that is gone is replaced by its nearest ancestor that can be
/// listed, or home. A tag that is gone is replaced by home. Back and Forward
/// entries that name a place that is gone are dropped, so Back skips them.
/// Nothing is listed here: the checks are existence checks, run off the main
/// thread.
public struct RestoredLocation: Sendable {
  /// Resolves a saved tab. Passed to a pane so tabs resolve as they show.
  public typealias Resolver = @Sendable (SavedTab) async -> SavedTab

  private let home: URL
  private let folders: any FolderChecking
  private let tags: any TagSource

  public init(
    home: URL, folders: any FolderChecking = DiskFolderChecker(),
    tags: any TagSource = SpotlightTagSource()
  ) {
    self.home = home
    self.folders = folders
    self.tags = tags
  }

  /// The resolver the app gives its pane.
  public var resolver: Resolver {
    { saved in await self.resolve(saved) }
  }

  public func resolve(_ saved: SavedTab) async -> SavedTab {
    // The tag list is read once, and only when a tag is involved.
    var tagNames: Set<String>?
    func tagExists(_ name: String) async -> Bool {
      if tagNames == nil {
        tagNames = Set(await tags.tags().map(\.name))
      }
      return tagNames?.contains(name) ?? false
    }

    func exists(_ url: URL) async -> Bool {
      if let virtual = VirtualLocation(url: url) {
        switch virtual {
        case .recents: return true
        case .tag(let name): return await tagExists(name)
        }
      }
      guard url.isFileURL else { return false }
      let folders = folders
      return await Task.detached { folders.isListableFolder(url) }.value
    }

    var result = saved
    let wanted = URL(string: saved.location)
    if let wanted, await exists(wanted) {
      // Where it was: keep everything.
    } else {
      let place = await nearestPlace(to: wanted)
      result.location = place.absoluteString
      // What was selected or open belongs to the folder that is gone.
      result.selection = []
      result.openFolders = []
    }

    func keep(_ entries: [SavedHistoryEntry]) async -> [SavedHistoryEntry] {
      var kept: [SavedHistoryEntry] = []
      for entry in entries {
        if let url = URL(string: entry.location), await exists(url) {
          kept.append(entry)
        }
      }
      return kept
    }
    result.back = await keep(saved.back)
    result.forward = await keep(saved.forward)
    return result
  }

  /// The nearest ancestor of a folder that can be listed, or home. A virtual
  /// location has no ancestors.
  func nearestPlace(to url: URL?) async -> URL {
    guard let url, url.isFileURL, !VirtualLocation.isVirtual(url) else { return home }
    // Built from the path's components, never by asking for a parent: on
    // macOS 15 the parent of "/" is "/..", and a loop up to a fixed point
    // never ends.
    var components = BrowserHistory.placeKey(url).split(separator: "/").map(String.init)
    let folders = folders
    while !components.isEmpty {
      components.removeLast()
      let candidate = URL(
        filePath: "/" + components.joined(separator: "/"), directoryHint: .isDirectory)
      if await Task.detached(operation: { folders.isListableFolder(candidate) }).value {
        return candidate
      }
    }
    return home
  }
}
