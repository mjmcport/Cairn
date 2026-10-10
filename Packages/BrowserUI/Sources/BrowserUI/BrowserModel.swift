import FileSystemCore
import Foundation
import os

/// The state of one browser: where it is, where it has been, what it shows
/// and what is selected. The view controller draws this and forwards user
/// actions to it.
@MainActor
public final class BrowserModel {
  public enum State: Equatable, Sendable {
    case loading
    case loaded
    /// The folder could not be listed; the text explains why.
    case failed(String)
  }

  /// Back and forward history. `history.current` is the folder being shown.
  public private(set) var history: BrowserHistory
  /// The folder's items after hidden-file filtering and sorting.
  public private(set) var items: [FileItem] = []
  public private(set) var state: State = .loading
  /// The selected items. The view writes this as the user selects; the model
  /// writes it when a navigation restores an earlier selection.
  public var selection: Set<URL> = []

  public var showsHiddenFiles = false
  public var sort = FileItemSort()

  /// Called on the main actor whenever the location, items, state or a
  /// restored selection changes.
  public var onChange: (() -> Void)?

  /// The folder being shown.
  public var location: URL { history.current }
  public var canGoBack: Bool { history.canGoBack }
  public var canGoForward: Bool { history.canGoForward }

  private let reader: any DirectoryReading
  /// Counts loads, so a slow listing of a folder the user has already left
  /// cannot overwrite the current one.
  private var generation = 0
  /// What to select once the folder being loaded has been listed.
  private var selectionToRestore: Set<URL>?
  /// What the history remembers for the folder being left. A folder left
  /// before its listing arrived still owes the selection it was waiting to
  /// restore; `selection` is empty until then.
  private var selectionLeftBehind: Set<URL> { selectionToRestore ?? selection }

  public init(location: URL, reader: any DirectoryReading = DirectoryReader()) {
    history = BrowserHistory(current: location)
    self.reader = reader
  }

  /// The signpost interval that covers a load, from the request until the
  /// view has been told about the result.
  public static let loadSignpostName: StaticString = "LoadFolder"

  /// Lists the current folder and publishes the result. Reloading the folder
  /// already showing keeps the selection of items that still exist.
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
      selection = Self.matching(selectionToRestore ?? selection, in: items)
      selectionToRestore = nil
      state = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard current == generation else { return }
      items = []
      selection = []
      selectionToRestore = nil
      state = .failed(error.localizedDescription)
    }
    onChange?()
  }

  // MARK: Moves
  //
  // Each move has two halves. The first changes the history and what is waiting
  // to be selected, and is synchronous, so a caller that starts the load in a
  // task can make the move as the command arrives: the next command then sees
  // where this one went. The second half is `load()`. The async functions
  // below do both for a caller that awaits.

  /// Records a move to another folder in the history, without listing it.
  /// Follow it with `load()`, also when the folder is the one already
  /// showing: that is a reload.
  /// - Returns: Whether the location changed.
  @discardableResult
  public func move(to folder: URL) -> Bool {
    guard !BrowserHistory.isSamePlace(folder, location) else { return false }
    history.visit(folder, leaving: selectionLeftBehind)
    prepareToShow(selecting: [])
    return true
  }

  /// Moves to the folder that contains the current one, without listing it.
  /// The folder just left is selected once ``load()`` has listed its parent.
  /// - Returns: Whether the location changed. It does not at the root.
  @discardableResult
  public func moveToEnclosingFolder() -> Bool {
    guard let parent = enclosingFolder else { return false }
    let child = location
    history.visit(parent, leaving: selectionLeftBehind)
    prepareToShow(selecting: [child])
    return true
  }

  /// Moves to the previous folder in the history, without listing it.
  /// - Returns: Whether the location changed. It does not without history.
  @discardableResult
  public func moveBack() -> Bool {
    guard let entry = history.goBack(leaving: selectionLeftBehind) else { return false }
    prepareToShow(selecting: entry.selection)
    return true
  }

  /// Undoes ``moveBack()``.
  @discardableResult
  public func moveForward() -> Bool {
    guard let entry = history.goForward(leaving: selectionLeftBehind) else { return false }
    prepareToShow(selecting: entry.selection)
    return true
  }

  /// Shows another folder and records the move in the history.
  public func navigate(to folder: URL) async {
    move(to: folder)
    await load()
  }

  /// Opens an item the way a double-click does. Folders are navigated into;
  /// opening files arrives later in Phase 1.
  /// - Returns: Whether the item was opened.
  @discardableResult
  public func open(_ item: FileItem) async -> Bool {
    guard item.isNavigable else { return false }
    await navigate(to: item.url)
    return true
  }

  /// The folder that contains the current one, or nil at the root.
  public var enclosingFolder: URL? {
    // The root is recognized by its path, not by asking for its parent: on
    // macOS 15 the parent of "/" comes back as "/..", which is not "/".
    let path = BrowserHistory.placeKey(location)
    guard path != "/", let lastSlash = path.lastIndex(of: "/") else { return nil }
    let parent = lastSlash == path.startIndex ? "/" : String(path[..<lastSlash])
    return URL(filePath: parent, directoryHint: .isDirectory)
  }

  /// Shows the folder that contains the current one, with the folder just
  /// left selected, as Finder does. Does nothing at the root.
  public func navigateToEnclosingFolder() async {
    guard moveToEnclosingFolder() else { return }
    await load()
  }

  /// Returns to the previous folder with its selection. Does nothing when
  /// there is no history.
  public func goBack() async {
    guard moveBack() else { return }
    await load()
  }

  /// Undoes ``goBack()``.
  public func goForward() async {
    guard moveForward() else { return }
    await load()
  }

  /// Empties the list after a move and remembers what to select once
  /// `history.current` has been listed.
  private func prepareToShow(selecting: Set<URL>) {
    items = []
    selection = []
    selectionToRestore = selecting
  }

  /// The URLs of `items` that `wanted` names. A selection belongs to one
  /// folder, so its items are matched by name. Their paths cannot be compared
  /// as text: a listing reports items under the folder its symbolic links
  /// lead to, and a location such as `/tmp/x` is not spelled that way.
  static func matching(_ wanted: Set<URL>, in items: [FileItem]) -> Set<URL> {
    guard !wanted.isEmpty else { return [] }
    let names = Set(wanted.map(\.lastPathComponent))
    return Set(items.filter { names.contains($0.name) }.map(\.url))
  }
}
