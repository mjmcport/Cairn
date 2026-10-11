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
  /// The folder's items after hidden-file filtering and sorting. While a
  /// large folder is loading they are its first rows, not yet sorted.
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
  /// What to select once the folder being loaded has settled, unless the
  /// user selects something first.
  private var selectionToRestore: Set<URL>?
  /// What is selected once the list settles, and what the history remembers
  /// for a folder left before then: what the user has selected since the
  /// move, or else what was waiting to be restored.
  private var selectionWanted: Set<URL> {
    selection.isEmpty ? selectionToRestore ?? [] : selection
  }

  /// Filters and sorts a whole folder. Never runs on the main actor.
  typealias Arrange =
    @Sendable (_ items: [FileItem], _ sort: FileItemSort, _ includingHidden: Bool) async throws
    -> [FileItem]
  private let arrange: Arrange

  public convenience init(location: URL, reader: any DirectoryReading = DirectoryReader()) {
    self.init(location: location, reader: reader) { items, sort, includingHidden in
      try await sort.arranged(items, includingHidden: includingHidden)
    }
  }

  /// - Parameter arrange: Tests replace it to hold a load while it sorts.
  init(location: URL, reader: any DirectoryReading, arrange: @escaping Arrange) {
    history = BrowserHistory(current: location)
    self.reader = reader
    self.arrange = arrange
  }

  /// The signpost interval that covers a load, from the request until the
  /// view has been told about the settled result.
  public static let loadSignpostName: StaticString = "LoadFolder"
  /// The signpost interval from the request until the list has rows: the
  /// first rows of a large folder, or the sorted list of a smaller one.
  public static let firstRowsSignpostName: StaticString = "FirstRows"

  /// Lists the current folder and publishes the result. A folder larger than
  /// one batch is published twice when the list is empty: its first rows,
  /// unsorted, while `state` is still `.loading`, and then the sorted list.
  /// Reloading the folder already showing keeps its rows until the sorted
  /// list replaces them, and keeps the selection of items that still exist.
  public func load() async {
    let signposter = Log.signposter
    let wholeLoad = signposter.beginInterval(Self.loadSignpostName)
    var firstRows: OSSignpostIntervalState? = signposter.beginInterval(Self.firstRowsSignpostName)
    func endFirstRows() {
      guard let interval = firstRows else { return }
      signposter.endInterval(Self.firstRowsSignpostName, interval)
      firstRows = nil
    }
    defer {
      endFirstRows()
      signposter.endInterval(Self.loadSignpostName, wholeLoad)
    }

    generation += 1
    let current = generation
    let folder = location
    state = .loading
    onChange?()

    // After every wait, a load that was superseded or cancelled stops
    // without publishing.
    func isStillWanted() -> Bool { current == generation && !Task.isCancelled }

    do {
      var listed: [FileItem]?
      for try await event in reader.listing(in: folder) {
        guard isStillWanted() else { return }
        switch event {
        case .firstItems(let first):
          // Only into an empty list: a reload keeps its rows until it settles.
          guard items.isEmpty else { continue }
          let rows = first.visible(includingHidden: showsHiddenFiles)
          guard !rows.isEmpty else { continue }
          items = rows
          onChange?()
          endFirstRows()
        case .allItems(let all):
          listed = all
        }
      }
      // A cancelled listing ends without throwing.
      guard isStillWanted() else { return }
      guard let listed else { throw DirectoryReadError.incomplete(folder) }
      let arranged = try await arrange(listed, sort, showsHiddenFiles)
      guard isStillWanted() else { return }
      items = arranged
      selection = Self.matching(selectionWanted, in: items)
      selectionToRestore = nil
      state = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard isStillWanted() else { return }
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
    history.visit(folder, leaving: selectionWanted)
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
    history.visit(parent, leaving: selectionWanted)
    prepareToShow(selecting: [child])
    return true
  }

  /// Moves to the previous folder in the history, without listing it.
  /// - Returns: Whether the location changed. It does not without history.
  @discardableResult
  public func moveBack() -> Bool {
    guard let entry = history.goBack(leaving: selectionWanted) else { return false }
    prepareToShow(selecting: entry.selection)
    return true
  }

  /// Undoes ``moveBack()``.
  @discardableResult
  public func moveForward() -> Bool {
    guard let entry = history.goForward(leaving: selectionWanted) else { return false }
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
    // Retires a load in flight now, not when the next one starts: the caller
    // may start that a turn later, and the old load must not publish the
    // folder just left into the list in between.
    generation += 1
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
