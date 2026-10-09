import FileSystemCore
import Foundation
import os

/// The state of one browser: where it is and what it shows. The view
/// controller draws this and forwards user actions to it.
@MainActor
public final class BrowserModel {
  public enum State: Equatable, Sendable {
    case loading
    case loaded
    /// The folder could not be listed; the text explains why.
    case failed(String)
  }

  /// The folder being shown.
  public private(set) var location: URL
  /// The folder's items after hidden-file filtering and sorting.
  public private(set) var items: [FileItem] = []
  public private(set) var state: State = .loading

  public var showsHiddenFiles = false
  public var sort = FileItemSort()

  /// Called on the main actor whenever `location`, `items` or `state` changes.
  public var onChange: (() -> Void)?

  private let reader: any DirectoryReading
  /// Counts loads, so a slow listing of a folder the user has already left
  /// cannot overwrite the current one.
  private var generation = 0

  public init(location: URL, reader: any DirectoryReading = DirectoryReader()) {
    self.location = location
    self.reader = reader
  }

  /// The signpost interval that covers a load, from the request until the
  /// view has been told about the result.
  public static let loadSignpostName: StaticString = "LoadFolder"

  /// Lists the current folder and publishes the result.
  public func load() async {
    let interval = Log.signposter.beginInterval(Self.loadSignpostName)
    defer { Log.signposter.endInterval(Self.loadSignpostName, interval) }

    generation += 1
    let current = generation
    let folder = location
    state = .loading
    onChange?()

    do {
      let listed = try await reader.items(in: folder)
      guard current == generation else { return }
      items = sort.sorted(listed.visible(includingHidden: showsHiddenFiles))
      state = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard current == generation else { return }
      items = []
      state = .failed(error.localizedDescription)
    }
    onChange?()
  }

  /// Shows another folder.
  public func navigate(to folder: URL) async {
    location = folder
    items = []
    await load()
  }

  /// Opens an item the way a double-click does. Folders are navigated into;
  /// opening files arrives in Phase 1.
  /// - Returns: Whether the item was opened.
  @discardableResult
  public func open(_ item: FileItem) async -> Bool {
    guard item.isNavigable else { return false }
    await navigate(to: item.url)
    return true
  }

  /// The folder that contains the current one, or nil at the root.
  public var enclosingFolder: URL? {
    let parent = location.deletingLastPathComponent()
    return parent.path == location.path ? nil : parent
  }

  /// Shows the folder that contains the current one. Does nothing at the root.
  public func navigateToEnclosingFolder() async {
    guard let enclosingFolder else { return }
    await navigate(to: enclosingFolder)
  }
}
