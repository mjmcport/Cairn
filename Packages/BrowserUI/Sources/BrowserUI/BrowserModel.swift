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

  /// What made the model call ``onChange``.
  public enum Publish: Equatable, Sendable {
    /// A load: the loading state, a folder's first rows, or its settled list.
    case load
    /// A change on disk to the folder already showing. The rows and the
    /// selection may have changed; where the user is looking has not.
    case refresh
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
  /// What the latest call of ``onChange`` was for.
  public private(set) var lastPublish = Publish.load

  /// The folder being shown.
  public var location: URL { history.current }
  public var canGoBack: Bool { history.canGoBack }
  public var canGoForward: Bool { history.canGoForward }

  private let reader: any DirectoryReading
  /// Nil for a model that never watches its folder.
  private let watcher: (any FolderWatching)?
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

  // MARK: Watching
  //
  // While the owner says the browser is on screen, one session watches the
  // folder being shown and answers each signal with a refresh, one at a
  // time. A move ends the session and starts the next. A load never
  // refreshes and a refresh never loads.

  /// Whether the owner has asked for the folder to be watched, and the model
  /// has a watcher to do it with.
  private(set) var isWatching = false
  /// The watch of the folder being shown, while there is one.
  private var session: WatchSession?
  private var sessionsStarted = 0
  /// Whether a signal arrived while a load was in flight. The load pays it
  /// with one refresh when it settles.
  private var owesRefresh = false
  /// Called each time a session has finished with every signal it had,
  /// whatever it did with them. Tests wait on it in place of a clock.
  var onSignalsAnswered: (() -> Void)?
  /// Whether the session has a signal it has not finished with.
  var isAnsweringSignals: Bool { session?.isAnswering ?? false }

  /// A browser on the real file system, which lists its folder and, while
  /// it is told to, watches it.
  public convenience init(location: URL) {
    self.init(location: location, reader: DirectoryReader(), watcher: FolderWatcher())
  }

  /// A browser that lists through `reader`. It watches nothing unless it is
  /// also given a watcher, so a test with a stub reader can never watch a
  /// real folder by leaving the watcher out.
  public convenience init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil
  ) {
    self.init(location: location, reader: reader, watcher: watcher) {
      items, sort, includingHidden in
      try await sort.arranged(items, includingHidden: includingHidden)
    }
  }

  /// - Parameter arrange: Tests replace it to hold a load while it sorts.
  init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil,
    arrange: @escaping Arrange
  ) {
    history = BrowserHistory(current: location)
    self.reader = reader
    self.watcher = watcher
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
    // Declared first, so it runs last: the signpost intervals have ended by
    // the time a signal that arrived during this load is answered.
    var settled = false
    defer {
      if settled, owesRefresh, let session {
        owesRefresh = false
        signalArrived(inSession: session.id)
      }
    }
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
    // This listing starts after every signal so far, so it answers them all.
    owesRefresh = false
    publish(.load)

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
          publish(.load)
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
    publish(.load)
    settled = true
  }

  private func publish(_ kind: Publish) {
    lastPublish = kind
    onChange?()
  }

  // MARK: Live updates

  /// Watches the folder being shown, and each folder the browser moves to,
  /// until ``stopWatching()``. The owner calls this while the browser is on
  /// screen. Every start is followed by one refresh, which brings up to date
  /// a list that nothing was watching. Does nothing in a model without a
  /// watcher, or one that is already watching.
  public func startWatching() {
    guard watcher != nil, !isWatching else { return }
    isWatching = true
    startSession()
  }

  /// Stops watching. A refresh under way publishes nothing.
  public func stopWatching() {
    guard isWatching else { return }
    isWatching = false
    endSession()
  }

  /// Ends the session in hand and, while watching, starts one for the folder
  /// now being shown. The folder's signals are asked for before this
  /// returns, so a command starts the new watch as it arrives.
  private func startSession() {
    endSession()
    guard isWatching, let watcher else { return }
    sessionsStarted += 1
    let id = sessionsStarted
    let signals = watcher.signals(for: location)
    session = WatchSession(
      id: id,
      // The task does not hold the model: when the model goes away the
      // session goes with it and ends the task, which stops the watch.
      forwarder: Task { [weak self] in
        for await _ in signals {
          self?.signalArrived(inSession: id)
        }
      })
  }

  private func endSession() {
    session?.end()
    session = nil
    owesRefresh = false
  }

  /// One signal for the session: from the watcher, or from a load paying
  /// what it owed. Signals that arrive while the session is busy are answered
  /// together, by exactly one more refresh.
  private func signalArrived(inSession id: Int) {
    guard let session, session.id == id else { return }
    session.hasSignal = true
    guard !session.isAnswering else { return }
    session.answering = Task { await self.answerSignals(of: session) }
  }

  /// Answers signals one at a time until the session has none: each is set
  /// aside during a load, and otherwise answered with a refresh.
  private func answerSignals(of session: WatchSession) async {
    while session === self.session, session.hasSignal {
      session.hasSignal = false
      if state == .loading {
        // The first rows of a load are never replaced by a refresh. The load
        // answers this signal when it settles.
        owesRefresh = true
      } else {
        await refresh(inSession: session.id)
      }
    }
    session.answering = nil
    onSignalsAnswered?()
  }

  /// Lists the folder again and publishes the result only when the visible
  /// rows changed, or when the folder could not be listed before and can be
  /// now, or the other way round. The whole listing, the filter, the sort and
  /// the comparison run off the main actor. Never shows the loading state,
  /// first rows or unsorted rows.
  ///
  /// A refresh reads the load counter and never changes it: a move or a load
  /// retires a refresh in flight, and a refresh can never retire a load.
  private func refresh(inSession id: Int) async {
    let current = generation
    let folder = location
    // After every wait, a refresh that was superseded by a move or a load,
    // or whose watch has stopped, stops without publishing.
    func isStillWanted() -> Bool {
      current == generation && session?.id == id && !Task.isCancelled
    }

    do {
      let listed = try await reader.items(in: folder)
      guard isStillWanted() else { return }
      let arranged = try await arrange(listed, sort, showsHiddenFiles)
      guard isStillWanted() else { return }
      let changed = await arranged.differs(from: items)
      guard isStillWanted() else { return }
      guard changed || state != .loaded else { return }
      items = arranged
      // From the selection as it is now: one the user made while the folder
      // was being listed is the one kept.
      selection = Self.matching(selectionWanted, in: items)
      selectionToRestore = nil
      state = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard isStillWanted() else { return }
      // A folder that went away is a refresh whose listing fails. The same
      // failure seen again is not news.
      let failure = State.failed(error.localizedDescription)
      guard state != failure else { return }
      items = []
      selection = []
      selectionToRestore = nil
      state = failure
    }
    publish(.refresh)
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
    // The watch moves with the browser, as the command arrives.
    startSession()
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

/// One watch of one folder: the task that passes the watcher's signals on,
/// and what the model has yet to do about them. The task ends when the
/// session goes away, and with it the watcher's stream, which stops the watch.
@MainActor
private final class WatchSession {
  let id: Int
  private let forwarder: Task<Void, Never>
  /// Whether a signal has arrived that no refresh has started to answer.
  var hasSignal = false
  /// The task answering signals, while there are any.
  var answering: Task<Void, Never>?
  var isAnswering: Bool { answering != nil }

  init(id: Int, forwarder: Task<Void, Never>) {
    self.id = id
    self.forwarder = forwarder
  }

  /// Stops the watch now, without waiting for a refresh under way to notice
  /// it is no longer wanted. That refresh stops at its next check;
  /// cancelling it also stops its listing.
  func end() {
    forwarder.cancel()
    answering?.cancel()
  }

  deinit {
    forwarder.cancel()
  }
}
