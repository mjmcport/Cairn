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
    /// A folder was opened or closed in place, or an open folder's rows
    /// changed. ``lastChangedFolder`` says which.
    case folder
    /// The sort changed and every level was put in the new order. The
    /// selection is where it was and is worth scrolling into view.
    case resort
    /// The way the folder is presented changed. The items, the selection and
    /// the location are as they were.
    case mode
  }

  /// How a folder is presented. The model's items, selection and sort are
  /// the same for both; only what is shown of them differs.
  public enum ViewMode: Sendable, Equatable {
    /// An outline of rows, in which folders open in place.
    case list
    /// A grid of pictures and names, in which a folder is entered.
    case icons
    /// A row of columns: the folders that lead to the selection, each
    /// listing the one selected in the column before it, and a preview.
    case columns
  }

  /// Back and forward history. `history.current` is the folder being shown.
  public private(set) var history: BrowserHistory
  /// The folder's items after hidden-file filtering and sorting. While a
  /// large folder is loading they are its first rows, not yet sorted.
  public private(set) var items: [FileItem] = []
  public private(set) var state: State = .loading
  /// The selected items. The view writes this as the user selects; the model
  /// writes it when a navigation restores an earlier selection.
  public var selection: Set<URL> = [] {
    didSet { if selection != oldValue { onStateChange?() } }
  }

  public var showsHiddenFiles = false {
    didSet { if showsHiddenFiles != oldValue { onStateChange?() } }
  }
  public var sort = FileItemSort() {
    didSet { if sort != oldValue { onStateChange?() } }
  }
  /// How this browser is presented. A tab's own, like its history.
  public private(set) var viewMode = ViewMode.list

  /// Called on the main actor whenever the location, items, state or a
  /// restored selection changes.
  public var onChange: (() -> Void)?
  /// Called when something a tab saves may have changed: its place, mode,
  /// sort, hidden files, open folders or selection.
  public var onStateChange: (() -> Void)?
  /// What the latest call of ``onChange`` was for.
  public private(set) var lastPublish = Publish.load
  /// The open folder the latest ``Publish/folder`` was about.
  public private(set) var lastChangedFolder: FolderKey?

  /// The folder being shown.
  public var location: URL { history.current }
  public var canGoBack: Bool { history.canGoBack }
  public var canGoForward: Bool { history.canGoForward }

  private let reader: any DirectoryReading
  /// Nil for a model that never watches its folder.
  private let watcher: (any FolderWatching)?
  private let settings: BrowserSettings
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
    let current = selection.isEmpty ? selectionToRestore ?? [] : selection
    // Items inside folders that are still being opened again are part of
    // what the user has selected, unless the user has selected since.
    guard !pendingSelection.isEmpty, selection.isEmpty || selection == selectionBaseline else {
      return current
    }
    return current.union(pendingSelection)
  }

  /// The folders to open again when the top level has settled, for a Back
  /// or Forward to a place that remembers them.
  private var foldersToRestore: Set<FolderKey> = []
  /// Selected items inside folders that have yet to be opened again, and
  /// the selection as the model last set it. The items are added as their
  /// folders appear, and only while the selection is still the one that
  /// was set: one the user made since is not replaced.
  private var pendingSelection: Set<URL> = []
  private var selectionBaseline: Set<URL>?
  /// Opens the remembered folders again, one at a time.
  private var restoreTask: Task<Void, Never>?

  /// Filters and sorts a whole folder. Never runs on the main actor.
  typealias Arrange =
    @Sendable (_ items: [FileItem], _ sort: FileItemSort, _ includingHidden: Bool) async throws
    -> [FileItem]
  private let arrange: Arrange

  /// The folders opened in place under the one being shown, by key. Each
  /// holds its own sorted items. They are closed by a move and kept, and
  /// listed again, by a reload.
  private(set) var openFolders: [FolderKey: OpenFolder] = [:]
  private var folderTokens = 0
  /// The listing of each open folder that is under way.
  private var folderTasks: [FolderKey: Task<Void, Never>] = [:]
  /// Lists the folders that were open again after a reload settles.
  private var reopenTask: Task<Void, Never>?
  /// Puts every level in a new sort order.
  private var resortTask: Task<Void, Never>?
  /// How many listings and passes over the open folders have started and
  /// not ended, retired ones included.
  private var activeFolderWork = 0
  private var idleWaiters: [CheckedContinuation<Void, Never>] = []

  // MARK: Watching
  //
  // While the owner says the browser is on screen, the folder being shown
  // and each folder open in it are watched, one session per folder. Every
  // session feeds one set of folders to look at again and one answerer,
  // which looks at them one at a time. A move ends every session and starts
  // the next. A load never refreshes and a refresh never loads.

  /// Whether the owner has asked for the folders to be watched, and the
  /// model has a watcher to do it with.
  private(set) var isWatching = false
  /// The watch of each folder being watched.
  private var sessions: [FolderKey: WatchSession] = [:]
  private var sessionsStarted = 0
  /// Folders with a signal that no refresh has started to answer.
  private var dirty: Set<FolderKey> = []
  /// Folders whose signal arrived while the top level was loading or their
  /// own listing was in flight. The listing that was in flight pays them
  /// with one refresh when it settles.
  private var owed: Set<FolderKey> = []
  /// The task answering signals, while there are any.
  private var answerer: Task<Void, Never>?
  /// Tells one answerer from the next, so one that was retired cannot clear
  /// the state of its successor.
  private var answererEpoch = 0
  /// Called each time an answerer has finished with every signal it had,
  /// whatever it did with them. Tests wait on it in place of a clock.
  var onSignalsAnswered: (() -> Void)?
  /// Whether there is a signal that has not been finished with.
  var isAnsweringSignals: Bool { answerer != nil }
  /// The keys of the folders being watched.
  var watchedFolders: Set<FolderKey> { Set(sessions.keys) }

  /// A browser on the real file system, which lists its folder and, while
  /// it is told to, watches it.
  public convenience init(location: URL) {
    self.init(
      location: location, reader: CompositeReader(), watcher: FolderWatcher(),
      settings: BrowserSettings())
  }

  /// A browser that lists through `reader`. It watches nothing unless it is
  /// also given a watcher, so a test with a stub reader can never watch a
  /// real folder by leaving the watcher out.
  public convenience init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil,
    settings: BrowserSettings = BrowserSettings()
  ) {
    self.init(location: location, reader: reader, watcher: watcher, settings: settings) {
      items, sort, includingHidden in
      try await sort.arranged(items, includingHidden: includingHidden)
    }
  }

  /// - Parameter arrange: Tests replace it to hold a load while it sorts.
  init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil,
    settings: BrowserSettings = BrowserSettings(), arrange: @escaping Arrange
  ) {
    history = BrowserHistory(current: location)
    self.reader = reader
    self.watcher = watcher
    self.settings = settings
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
    // The folders being listed again after a reload answer their own signals.
    var listedAgain: Set<FolderKey> = []
    defer {
      if settled {
        payOwed(except: listedAgain)
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

    // A reload keeps the folders that are open. They are listed again, one
    // at a time, once this listing has settled.
    let reopening = openFolders.keys.sorted { $0.depth < $1.depth }
    cancelFolderTasks()

    generation += 1
    let current = generation
    let folder = location
    state = .loading
    // This listing starts after every signal so far, so it answers them all.
    owed = []
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
      let wanted = selectionWanted
      selection = resolveSelection(wanted)
      // What was selected inside folders that have yet to be opened again
      // is kept until they are.
      pendingSelection =
        foldersToRestore.isEmpty ? [] : wanted.filter { resolveSelection([$0]).isEmpty }
      selectionBaseline = selection
      selectionToRestore = nil
      state = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard isStillWanted() else { return }
      items = []
      selection = []
      selectionToRestore = nil
      openFolders = [:]
      state = .failed(error.localizedDescription)
    }
    publish(.load)
    settled = true
    if state == .loaded, !reopening.isEmpty {
      listedAgain = Set(reopening)
      listAgain(reopening, generation: current)
    }
    if state == .loaded, !foldersToRestore.isEmpty {
      let keys = foldersToRestore
      foldersToRestore = []
      restoreOpenFolders(keys, generation: current)
    }
  }

  private func publish(_ kind: Publish) {
    lastPublish = kind
    onChange?()
    onStateChange?()
  }

  // MARK: Live updates

  /// Watches the folder being shown, each folder open in it, and each folder
  /// the browser moves to, until ``stopWatching()``. The owner calls this
  /// while the browser is on screen. Every start is followed by one refresh,
  /// which brings up to date a list that nothing was watching. Does nothing
  /// in a model without a watcher, or one that is already watching.
  public func startWatching() {
    guard watcher != nil, !isWatching else { return }
    isWatching = true
    startSessions()
    // Folders opened while nothing was watching are brought up to date by
    // the look that follows the start of their watch.
    for key in openFolders.keys {
      if let item = item(at: key) { startSession(for: key, at: item.url) }
    }
  }

  /// Stops watching. A refresh under way publishes nothing.
  public func stopWatching() {
    guard isWatching else { return }
    isWatching = false
    endAllSessions()
  }

  /// Ends every session and, while watching, starts one for the folder now
  /// being shown. The folder's signals are asked for before this returns, so
  /// a command starts the new watch as it arrives.
  private func startSessions() {
    endAllSessions()
    guard isWatching else { return }
    startSession(for: .root, at: location)
  }

  private func startSession(for key: FolderKey, at folder: URL) {
    // A virtual location has no folder to watch.
    guard isWatching, let watcher, sessions[key] == nil, !VirtualLocation.isVirtual(folder)
    else { return }
    sessionsStarted += 1
    let id = sessionsStarted
    let signals = watcher.signals(for: folder)
    sessions[key] = WatchSession(
      id: id,
      // The task does not hold the model: when the model goes away the
      // session goes with it and ends the task, which stops the watch.
      forwarder: Task { [weak self] in
        for await _ in signals {
          self?.signalArrived(for: key, inSession: id)
        }
      })
  }

  private func endSession(for key: FolderKey) {
    sessions[key]?.end()
    sessions[key] = nil
    dirty.remove(key)
    owed.remove(key)
  }

  private func endAllSessions() {
    for session in sessions.values { session.end() }
    sessions = [:]
    dirty = []
    owed = []
    answerer?.cancel()
    answerer = nil
    answererEpoch += 1
  }

  /// One signal for a folder's session, from the watcher. A signal for a
  /// session that has ended is ignored.
  private func signalArrived(for key: FolderKey, inSession id: Int) {
    guard sessions[key]?.id == id else { return }
    markDirty(key)
  }

  /// Asks for the folder to be looked at again. Signals that arrive while
  /// the answerer is busy are answered together, by one more refresh each.
  private func markDirty(_ key: FolderKey) {
    guard sessions[key] != nil else { return }
    dirty.insert(key)
    guard answerer == nil else { return }
    answererEpoch += 1
    let epoch = answererEpoch
    answerer = Task { @MainActor [weak self] in
      await self?.answerSignals(epoch: epoch)
    }
  }

  /// Answers signals one folder at a time, shallowest first, until there are
  /// none: each is set aside while its folder or the top level is being
  /// listed, and otherwise answered with a refresh of that folder.
  private func answerSignals(epoch: Int) async {
    while epoch == answererEpoch, let key = dirty.min(by: { $0.depth < $1.depth }) {
      dirty.remove(key)
      guard let session = sessions[key] else { continue }
      if state == .loading || (!key.isRoot && openFolders[key]?.listing == .listing) {
        // The first rows of a load are never replaced by a refresh, and a
        // folder is not looked at again while it is being listed. The
        // listing answers this signal when it settles.
        owed.insert(key)
      } else {
        await refresh(key, inSession: session.id)
      }
    }
    if epoch == answererEpoch {
      answerer = nil
    }
    onSignalsAnswered?()
  }

  /// Answers the signals that were set aside for `keys`, or for every
  /// folder when `keys` is nil. A folder named in `excluded` is being listed
  /// again by a reload, which answers its signals: they are dropped.
  private func payOwed(for keys: Set<FolderKey>? = nil, except excluded: Set<FolderKey> = []) {
    owed.subtract(excluded)
    let due = owed.filter { keys?.contains($0) ?? true }
    owed.subtract(due)
    for key in due { markDirty(key) }
  }

  /// Lists the folder at `key` again and publishes the result only when the
  /// visible rows changed, or when the folder could not be listed before and
  /// can be now, or the other way round. The whole listing, the filter, the
  /// sort and the comparison run off the main actor. Never shows the loading
  /// state, first rows or unsorted rows.
  ///
  /// A refresh reads the load counter and never changes it: a move, a load,
  /// a close or a newer opening retires a refresh in flight, and a refresh
  /// can never retire any of them.
  private func refresh(_ key: FolderKey, inSession id: Int) async {
    let current = generation
    // A folder that is no longer listed has nothing to look at.
    guard let folder = key.isRoot ? location : item(at: key)?.url else { return }
    let token = openFolders[key]?.token
    // After every wait, a refresh that was superseded by a move, a load or a
    // close, or whose watch has stopped, stops without publishing.
    func isStillWanted() -> Bool {
      current == generation && sessions[key]?.id == id && openFolders[key]?.token == token
        && (key.isRoot || token != nil) && !Task.isCancelled
    }

    do {
      let listed = try await reader.items(in: folder)
      guard isStillWanted() else { return }
      let arranged = try await arrange(listed, sort, showsHiddenFiles)
      guard isStillWanted() else { return }
      let shown = key.isRoot ? items : openFolders[key]?.items ?? []
      let changed = await arranged.differs(from: shown)
      guard isStillWanted() else { return }
      if key.isRoot {
        guard changed || state != .loaded else { return }
        items = arranged
        state = .loaded
      } else {
        guard changed || openFolders[key]?.listing != .listed else { return }
        openFolders[key]?.items = arranged
        openFolders[key]?.listing = .listed
      }
      // A folder that went away inside the one just listed is closed here.
      closeFoldersThatAreGone()
      // From the selection as it is now: one the user made while the folder
      // was being listed is the one kept.
      selection = resolveSelection(selectionWanted)
      selectionToRestore = nil
    } catch is CancellationError {
      return
    } catch {
      guard isStillWanted() else { return }
      // A folder that went away is a refresh whose listing fails. The same
      // failure seen again is not news.
      if key.isRoot {
        let failure = State.failed(error.localizedDescription)
        guard state != failure else { return }
        items = []
        selection = []
        selectionToRestore = nil
        openFolders = [:]
        endSessions(except: .root)
        state = failure
      } else {
        let failure = OpenFolder.Listing.failed(error.localizedDescription)
        guard openFolders[key]?.listing != failure else { return }
        dropSelection(insideFolderOf: key)
        openFolders[key]?.items = []
        openFolders[key]?.listing = failure
        closeFoldersThatAreGone()
      }
    }
    if key.isRoot {
      publish(.refresh)
    } else {
      lastChangedFolder = key
      publish(.folder)
    }
  }

  /// Ends the watch of every folder but `key`'s.
  private func endSessions(except key: FolderKey) {
    for other in sessions.keys where other != key {
      endSession(for: other)
    }
  }

  // MARK: Open folders
  //
  // A folder in the list can be opened in place. It is listed like any
  // folder, off the main actor, and publishes its rows once they are sorted.
  // Opening and closing are synchronous, like moves: the state changes as
  // the command arrives and only the listing runs in a task. Each open
  // folder has its own token, and every listing also carries the load
  // counter, so a move, a load or a close retires a listing in flight.

  /// The item at `key`, found in the rows of its folder, or nil when that
  /// folder is not open and listed or holds no such item.
  func item(at key: FolderKey) -> FileItem? {
    guard let name = key.names.last, let parent = key.parent else { return nil }
    let rows = parent.isRoot ? items : openFolders[parent]?.items
    return rows?.first { $0.name == name }
  }

  /// What the open folder at `key` holds, sorted. Empty for a folder that
  /// is not open.
  public func children(of key: FolderKey) -> [FileItem] {
    key.isRoot ? items : openFolders[key]?.items ?? []
  }

  /// The keys of the folders open in place, shallowest first, so a view can
  /// open them parent before child.
  public var openFolderKeys: [FolderKey] {
    openFolders.keys.sorted {
      $0.depth != $1.depth
        ? $0.depth < $1.depth : $0.names.joined(separator: "/") < $1.names.joined(separator: "/")
    }
  }

  /// Whether the folder at `key` is open in place.
  public func isOpen(_ key: FolderKey) -> Bool {
    openFolders[key] != nil
  }

  /// Why the open folder at `key` could not be listed, or nil.
  public func failure(of key: FolderKey) -> String? {
    guard case .failed(let reason) = openFolders[key]?.listing else { return nil }
    return reason
  }

  /// Opens the folder at `key` in place and starts listing it. Opening is
  /// not a move: history, the title and tabs are untouched.
  /// - Returns: Whether a folder was opened. Not for a file, a package, a
  ///   folder that is not listed, or one that is already open.
  @discardableResult
  public func openFolder(_ key: FolderKey) -> Bool {
    // A virtual location is a flat list: its names are not unique, and a
    // folder's place in it is not a place under the location.
    guard !isShowingVirtualLocation, openFolders[key] == nil, let item = item(at: key),
      item.isNavigable
    else {
      return false
    }
    folderTokens += 1
    let token = folderTokens
    openFolders[key] = OpenFolder(token: token)
    startSession(for: key, at: item.url)
    lastChangedFolder = key
    publish(.folder)
    folderTasks[key] = startFolderWork {
      await $0.listOpenFolder(key, token: token, at: item.url, publishesOnlyChanges: false)
    }
    return true
  }

  /// Closes the folder at `key` and everything open inside it. What was
  /// selected inside is dropped from the selection, and the folder is
  /// selected in its place when something was.
  /// - Returns: Whether a folder was closed.
  @discardableResult
  public func closeFolder(_ key: FolderKey) -> Bool {
    guard openFolders[key] != nil else { return false }
    let folderURL = item(at: key)?.url
    let dropped = removeFolder(key)
    if !selection.isDisjoint(with: dropped) {
      selection.subtract(dropped)
      if let folderURL { selection.insert(folderURL) }
    }
    lastChangedFolder = key
    publish(.folder)
    return true
  }

  /// Lists the folder at `key`, arranges it and stores the rows.
  ///
  /// After every wait it stops, without publishing, unless the load counter
  /// is the one it started under and the folder is still open as the same
  /// opening. It reads the counter and never changes it.
  /// - Parameter publishesOnlyChanges: For a folder that already shows rows,
  ///   which are kept until the new ones replace them, and are replaced
  ///   without a publish when nothing visible changed.
  private func listOpenFolder(
    _ key: FolderKey, token: Int, at url: URL, publishesOnlyChanges: Bool
  ) async {
    let settled = await listOpenFolderOnce(
      key, token: token, at: url, publishesOnlyChanges: publishesOnlyChanges)
    // A signal that arrived while the folder was being listed is answered
    // now, by one refresh, unless the listing was retired.
    if settled { payOwed(for: [key]) }
  }

  /// - Returns: Whether the listing ended as the folder's own, rather than
  ///   being retired by a move, a load or a close.
  private func listOpenFolderOnce(
    _ key: FolderKey, token: Int, at url: URL, publishesOnlyChanges: Bool
  ) async -> Bool {
    let current = generation
    func isStillWanted() -> Bool {
      current == generation && openFolders[key]?.token == token && !Task.isCancelled
    }
    let arranged: [FileItem]
    do {
      let listed = try await reader.items(in: url)
      guard isStillWanted() else { return false }
      arranged = try await arrange(listed, sort, showsHiddenFiles)
      guard isStillWanted() else { return false }
    } catch is CancellationError {
      return false
    } catch {
      guard isStillWanted() else { return false }
      let failure = OpenFolder.Listing.failed(error.localizedDescription)
      // The same failure seen again is not news.
      guard openFolders[key]?.listing != failure else { return true }
      dropSelection(insideFolderOf: key)
      openFolders[key]?.items = []
      openFolders[key]?.listing = failure
      closeFoldersThatAreGone()
      lastChangedFolder = key
      publish(.folder)
      return true
    }
    if publishesOnlyChanges, openFolders[key]?.listing == .listed {
      let changed = await arranged.differs(from: openFolders[key]?.items ?? [])
      guard isStillWanted() else { return false }
      guard changed else { return true }
    }
    openFolders[key]?.items = arranged
    openFolders[key]?.listing = .listed
    // A folder that went away inside this one is closed with this listing.
    closeFoldersThatAreGone()
    // What was selected in the folder and still exists stays selected.
    selection = resolveSelection(selection)
    applyPendingSelection()
    lastChangedFolder = key
    publish(.folder)
    return true
  }

  /// Closes, without publishing, every open folder whose item is no longer
  /// listed or is no longer a folder, with what was open inside it and their
  /// selection. The caller publishes.
  private func closeFoldersThatAreGone() {
    for key in openFolders.keys.sorted(by: { $0.depth < $1.depth }) where openFolders[key] != nil {
      if let item = item(at: key), item.isNavigable { continue }
      let dropped = removeFolder(key)
      selection.subtract(dropped)
    }
  }

  /// Takes the folder at `key` and everything open inside it out of the
  /// tree, ending their listings and watches.
  /// - Returns: The URLs of every item they held.
  @discardableResult
  private func removeFolder(_ key: FolderKey) -> Set<URL> {
    var dropped = Set<URL>()
    for (other, folder) in openFolders where other.isInside(key) {
      dropped.formUnion(folder.items.map(\.url))
      folderTasks[other]?.cancel()
      folderTasks[other] = nil
      endSession(for: other)
    }
    openFolders = openFolders.filter { !$0.key.isInside(key) }
    return dropped
  }

  /// Drops every selected item that lay inside the folder at `key`.
  private func dropSelection(insideFolderOf key: FolderKey) {
    let urls = Set((openFolders[key]?.items ?? []).map(\.url))
    selection.subtract(urls)
  }

  /// Lists again, one at a time and shallowest first, the folders that were
  /// open before a reload. A folder that is no longer there is closed,
  /// with what was open inside it.
  private func listAgain(_ keys: [FolderKey], generation current: Int) {
    reopenTask?.cancel()
    reopenTask = startFolderWork { model in
      for key in keys {
        guard !Task.isCancelled, model.generation == current else { return }
        guard model.openFolders[key] != nil else { continue }
        guard let item = model.item(at: key), item.isNavigable else {
          model.closeFolder(key)
          continue
        }
        let token = model.openFolders[key]?.token ?? 0
        await model.listOpenFolder(key, token: token, at: item.url, publishesOnlyChanges: true)
      }
    }
  }

  private func cancelFolderTasks() {
    for task in folderTasks.values { task.cancel() }
    folderTasks = [:]
    reopenTask?.cancel()
    reopenTask = nil
    resortTask?.cancel()
    resortTask = nil
    restoreTask?.cancel()
    restoreTask = nil
  }

  /// Runs `work` as a task and counts it until it ends, so a test can wait
  /// for work that a move or a close has already retired.
  private func startFolderWork(
    _ work: @escaping @MainActor (BrowserModel) async -> Void
  ) -> Task<Void, Never> {
    activeFolderWork += 1
    return Task { @MainActor [weak self] in
      guard let self else { return }
      await work(self)
      self.activeFolderWork -= 1
      if self.activeFolderWork == 0 {
        let waiters = self.idleWaiters
        self.idleWaiters = []
        for waiter in waiters { waiter.resume() }
      }
    }
  }

  /// Waits until every listing and pass of the open folders has ended,
  /// including ones that were retired. Tests await it in place of a clock.
  func waitForOpenFolders() async {
    while activeFolderWork > 0 {
      await withCheckedContinuation { idleWaiters.append($0) }
    }
  }

  // MARK: Opening folders again
  //
  // A history entry remembers the folders that were open when the place was
  // left. Going Back or Forward to it, with the setting on, opens them again
  // once the top level has settled: shallowest first, one at a time, each
  // through the same path as the user's own opening, so each follows the
  // rules of the load counter and the folder's token.

  /// Opens `keys` again, in order. A key whose folder is gone, is no longer
  /// a folder, or is already open is skipped without a message.
  private func restoreOpenFolders(_ keys: Set<FolderKey>, generation current: Int) {
    let ordered = keys.sorted {
      $0.depth != $1.depth
        ? $0.depth < $1.depth : $0.names.joined(separator: "/") < $1.names.joined(separator: "/")
    }
    restoreTask?.cancel()
    restoreTask = startFolderWork { model in
      for key in ordered {
        guard !Task.isCancelled, model.generation == current else { break }
        guard model.openFolders[key] == nil, let item = model.item(at: key), item.isNavigable
        else { continue }
        guard model.openFolder(key) else { continue }
        await model.folderTasks[key]?.value
      }
      // Nothing more is coming, or what was coming has been retired.
      if model.generation == current {
        model.pendingSelection = []
        model.selectionBaseline = nil
      }
    }
  }

  /// Selects what was selected inside a folder that has just been listed,
  /// as long as the selection is still the one the model set.
  private func applyPendingSelection() {
    guard !pendingSelection.isEmpty else { return }
    guard selection == selectionBaseline else {
      pendingSelection = []
      selectionBaseline = nil
      return
    }
    let found = resolveSelection(pendingSelection)
    guard !found.isEmpty else { return }
    selection.formUnion(found)
    selectionBaseline = selection
    pendingSelection = pendingSelection.filter { resolveSelection([$0]).isEmpty }
  }

  // MARK: Saved state

  /// What a tab remembers across launches: where it is and how it is shown.
  /// Reads only values the model already holds, so it is safe on the main
  /// actor and never lists anything.
  public func captureState() -> SavedTab {
    func strings(_ urls: Set<URL>) -> [String] { urls.map(\.absoluteString).sorted() }
    func names(_ keys: Set<FolderKey>) -> [[String]] {
      keys.map(\.names).sorted { $0.lexicographicallyPrecedes($1) }
    }
    func entry(_ entry: BrowserHistory.Entry) -> SavedHistoryEntry {
      SavedHistoryEntry(
        location: entry.location.absoluteString, selection: strings(entry.selection),
        openFolders: names(entry.openFolders))
    }
    return SavedTab(
      location: location.absoluteString,
      viewMode: SavedViewMode(viewMode),
      sort: SavedSort(sort),
      showsHidden: showsHiddenFiles,
      openFolders: names(foldersToRemember),
      selection: strings(selectionWanted),
      back: history.backEntries.map(entry),
      forward: history.forwardEntries.map(entry))
  }

  /// Puts a saved tab's presentation and history on a model that has not
  /// listed anything yet. Follow it with ``load()``. The saved location
  /// becomes the model's own; the caller has already replaced a folder that
  /// no longer exists (see ``RestoredLocation``).
  ///
  /// Open folders are restored in the list only: the icon view has none and
  /// the column view derives its columns from the selection.
  public func restore(_ saved: SavedTab) {
    viewMode = saved.viewMode.browserMode
    sort = saved.sort.fileItemSort
    showsHiddenFiles = saved.showsHidden
    func urls(_ strings: [String]) -> Set<URL> { Set(strings.compactMap { URL(string: $0) }) }
    func keys(_ names: [[String]]) -> Set<FolderKey> { Set(names.map { FolderKey(names: $0) }) }
    func entry(_ saved: SavedHistoryEntry) -> BrowserHistory.Entry? {
      guard let location = URL(string: saved.location) else { return nil }
      return BrowserHistory.Entry(
        location: location, selection: urls(saved.selection), openFolders: keys(saved.openFolders))
    }
    history = BrowserHistory(
      current: URL(string: saved.location) ?? history.current,
      back: saved.back.compactMap(entry),
      forward: saved.forward.compactMap(entry))
    selectionToRestore = urls(saved.selection)
    foldersToRestore = viewMode == .list ? keys(saved.openFolders) : []
  }

  // MARK: Mode

  /// Shows the folder as `mode`. Switching to icons closes every folder that
  /// is open in place, because the icon view shows the top level only and a
  /// selection a person cannot see would be a selection nobody can change:
  /// what was selected inside a folder falls back to the folder, as when the
  /// user closes it. Nothing is listed again and history is untouched.
  public func setViewMode(_ mode: ViewMode) {
    guard mode != viewMode else { return }
    viewMode = mode
    switch mode {
    case .list:
      // The folders that are open stay open: the list shows them.
      break
    case .icons:
      for key in openFolders.keys where key.depth == 1 {
        closeFolderQuietly(key)
      }
    case .columns:
      pruneOpenFolders(keepingPathTo: selection)
    }
    publish(.mode)
  }

  /// Closes `key` and what is open inside it without publishing. What was
  /// selected inside falls back to the folder, as when the user closes it.
  private func closeFolderQuietly(_ key: FolderKey) {
    let folderURL = item(at: key)?.url
    let dropped = removeFolder(key)
    if !selection.isDisjoint(with: dropped) {
      selection.subtract(dropped)
      if let folderURL { selection.insert(folderURL) }
    }
  }

  /// The selected items that are listed, at any level, in no particular
  /// order. A selected URL that is not listed is not in the result.
  var selectedItems: [FileItem] {
    guard !selection.isEmpty else { return [] }
    var found = items.filter { selection.contains($0.url) }
    for folder in openFolders.values {
      found += folder.items.filter { selection.contains($0.url) }
    }
    return found
  }

  /// The key of the item with this URL in the top level or an open folder,
  /// or nil when it is not listed.
  func key(of url: URL) -> FolderKey? {
    if let item = items.first(where: { $0.url == url }) {
      return FolderKey.root.appending(item.name)
    }
    for (folder, contents) in openFolders {
      if let item = contents.items.first(where: { $0.url == url }) {
        return folder.appending(item.name)
      }
    }
    return nil
  }

  /// Closes every open folder that is not on the way to `selection`. The
  /// way to a selection is the chain of folders that lead to the folder the
  /// selected items are in, and the selected folder itself when it is the
  /// only item selected and is open. With nothing selected, or items in
  /// different folders, no folder is kept.
  func pruneOpenFolders(keepingPathTo selection: Set<URL>) {
    let keys = selection.compactMap { key(of: $0) }
    var keep = Set<FolderKey>()
    if !selection.isEmpty, keys.count == selection.count,
      Set(keys.map { $0.parent ?? .root }).count == 1, let parent = keys[0].parent
    {
      var next: FolderKey? = parent
      while let key = next, !key.isRoot {
        keep.insert(key)
        next = key.parent
      }
      if keys.count == 1, openFolders[keys[0]] != nil { keep.insert(keys[0]) }
    }
    for key in openFolders.keys.sorted(by: { $0.depth < $1.depth })
    where openFolders[key] != nil && !keep.contains(key) {
      closeFolderQuietly(key)
    }
  }

  // MARK: Sort

  /// Puts the top level and every listed open folder in `newSort` order
  /// and publishes once. The pass runs off the main actor and stops, without
  /// publishing, when a move or a load retires it.
  public func changeSort(to newSort: FileItemSort) {
    guard newSort != sort else { return }
    sort = newSort
    resortTask?.cancel()
    let current = generation
    let wanted = newSort
    let includingHidden = showsHiddenFiles
    let topLevel = items
    let folders = openFolders.compactMap { key, folder in
      folder.listing == .listed ? (key, folder.token, folder.items) : nil
    }
    resortTask = startFolderWork { model in
      let isStillWanted: @MainActor () -> Bool = {
        current == model.generation && model.sort == wanted && !Task.isCancelled
      }
      do {
        let top = try await model.arrange(topLevel, wanted, includingHidden)
        guard isStillWanted() else { return }
        var arrangedFolders: [(FolderKey, Int, [FileItem])] = []
        for (key, token, rows) in folders {
          let arranged = try await model.arrange(rows, wanted, includingHidden)
          guard isStillWanted() else { return }
          arrangedFolders.append((key, token, arranged))
        }
        model.items = top
        for (key, token, rows) in arrangedFolders where model.openFolders[key]?.token == token {
          model.openFolders[key]?.items = rows
        }
        model.publish(.resort)
      } catch {
        return
      }
    }
  }

  // MARK: Selection across levels

  /// The items of the tree that `wanted` names, as the URLs the tree holds.
  ///
  /// A wanted URL names an item in one of three ways. It may be the item's
  /// own URL, which is what the list writes. It may spell the path from the
  /// location as it was opened, or from the folder the listing followed,
  /// which differ when a symbolic link is in the way; the names below that
  /// root are looked up level by level. Or it may be outside both, as the
  /// folder just left is on Enclosing Folder, and then a top-level item of
  /// the same name is meant, as it always was.
  func resolveSelection(_ wanted: Set<URL>) -> Set<URL> {
    guard !wanted.isEmpty else { return [] }
    let wantedNames = Set(wanted.map(\.lastPathComponent))
    var byPath: [String: URL] = [:]
    for item in items where wantedNames.contains(item.name) {
      byPath[BrowserHistory.placeKey(item.url)] = item.url
    }
    for folder in openFolders.values {
      for item in folder.items where wantedNames.contains(item.name) {
        byPath[BrowserHistory.placeKey(item.url)] = item.url
      }
    }
    let spelledRoot = BrowserHistory.placeKey(location)
    let listedRoot = items.first.map { BrowserHistory.placeKey($0.url.deletingLastPathComponent()) }

    var found = Set<URL>()
    for url in wanted {
      let path = BrowserHistory.placeKey(url)
      if let hit = byPath[path] {
        found.insert(hit)
        continue
      }
      var nested = false
      var hit: URL?
      for root in [spelledRoot, listedRoot].compactMap({ $0 }) {
        guard let names = Self.names(of: path, below: root) else { continue }
        nested = nested || names.count > 1
        if let item = lookUp(names) {
          hit = item.url
          break
        }
      }
      if let hit {
        found.insert(hit)
      } else if !nested, let item = items.first(where: { $0.name == url.lastPathComponent }) {
        found.insert(item.url)
      }
    }
    return found
  }

  /// The path's names below `root`, or nil when it is not below it.
  private static func names(of path: String, below root: String) -> [String]? {
    let prefix = root == "/" ? "/" : root + "/"
    guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
    return path.dropFirst(prefix.count).split(separator: "/").map(String.init)
  }

  /// The item reached by `names` from the top level, through open folders.
  private func lookUp(_ names: [String]) -> FileItem? {
    var key = FolderKey.root
    var found: FileItem?
    for name in names {
      let rows = key.isRoot ? items : openFolders[key]?.items
      guard let item = rows?.first(where: { $0.name == name }) else { return nil }
      found = item
      key = key.appending(name)
    }
    return found
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
  /// - Parameter selecting: Items to select once the folder is listed, such
  ///   as the file a typed path named.
  /// - Returns: Whether the location changed.
  @discardableResult
  public func move(to folder: URL, selecting: Set<URL> = []) -> Bool {
    guard !BrowserHistory.isSamePlace(folder, location) else { return false }
    history.visit(folder, leaving: selectionWanted, openFolders: foldersToRemember)
    prepareToShow(selecting: selecting)
    return true
  }

  /// Moves to the folder that contains the current one, without listing it.
  /// The folder just left is selected once ``load()`` has listed its parent.
  /// - Returns: Whether the location changed. It does not at the root.
  @discardableResult
  public func moveToEnclosingFolder() -> Bool {
    guard let parent = enclosingFolder else { return false }
    let child = location
    history.visit(parent, leaving: selectionWanted, openFolders: foldersToRemember)
    prepareToShow(selecting: [child])
    return true
  }

  /// Moves to the previous folder in the history, without listing it.
  /// - Returns: Whether the location changed. It does not without history.
  @discardableResult
  public func moveBack() -> Bool {
    guard let entry = history.goBack(leaving: selectionWanted, openFolders: foldersToRemember)
    else { return false }
    prepareToShow(selecting: entry.selection, restoring: entry.openFolders)
    return true
  }

  /// Undoes ``moveBack()``.
  @discardableResult
  public func moveForward() -> Bool {
    guard let entry = history.goForward(leaving: selectionWanted, openFolders: foldersToRemember)
    else { return false }
    prepareToShow(selecting: entry.selection, restoring: entry.openFolders)
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

  /// Whether the location is a tag or the recents, not a folder.
  public var isShowingVirtualLocation: Bool { VirtualLocation.isVirtual(location) }

  /// The folder that contains the current one, or nil at the root and in a
  /// virtual location, which is inside nothing.
  public var enclosingFolder: URL? {
    guard !isShowingVirtualLocation else { return nil }
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
  /// The folders a history entry should remember for the place being left:
  /// those open now, and those that were waiting to be opened again.
  private var foldersToRemember: Set<FolderKey> {
    Set(openFolders.keys).union(foldersToRestore)
  }

  /// - Parameter restoring: The folders to open again once the place has
  ///   been listed, from the history entry returned to. They are used only
  ///   when the setting is on, and are read when the move is made.
  private func prepareToShow(selecting: Set<URL>, restoring: Set<FolderKey> = []) {
    // Retires a load in flight now, not when the next one starts: the caller
    // may start that a turn later, and the old load must not publish the
    // folder just left into the list in between.
    generation += 1
    cancelFolderTasks()
    openFolders = [:]
    foldersToRestore = settings.rememberOpenFolders ? restoring : []
    pendingSelection = []
    selectionBaseline = nil
    items = []
    selection = []
    selectionToRestore = selecting
    // The watch moves with the browser, as the command arrives.
    startSessions()
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

/// One watch of one folder: the task that passes the watcher's signals on.
/// The task ends when the session goes away, and with it the watcher's
/// stream, which stops the watch.
@MainActor
private final class WatchSession {
  let id: Int
  private let forwarder: Task<Void, Never>

  init(id: Int, forwarder: Task<Void, Never>) {
    self.id = id
    self.forwarder = forwarder
  }

  /// Stops the watch now, without waiting for a refresh under way to notice
  /// it is no longer wanted. That refresh stops at its next check.
  func end() {
    forwarder.cancel()
  }

  deinit {
    forwarder.cancel()
  }
}
