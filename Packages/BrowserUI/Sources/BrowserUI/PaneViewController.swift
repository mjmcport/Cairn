import AppKit
import FileSystemCore

/// One pane of a window: a row of tabs over the browser of the tab that is
/// showing. A window's content is one of these.
///
/// Each tab is a whole ``BrowserViewController``, kept alive while its tab is
/// open, so a tab that is not showing keeps its folder, history, selection
/// and scroll position, and finishes a listing it had started. Only the
/// showing browser's view is in the window. A browser's view lists its folder
/// when it loads, so a tab that has never been shown has listed nothing.
///
/// Only the showing tab watches its folder for changes, and only while the
/// pane is on screen. A tab that comes back on screen brings its list up to
/// date as its watch starts.
///
/// The pane owns what a browser cannot know about: the window's title,
/// keyboard focus after the showing tab changes, and the tab bar. The Go
/// commands still travel the responder chain to a browser; the pane offers
/// the showing one when keyboard focus is on the tab bar.
@MainActor
public final class PaneViewController: NSViewController {
  /// The tabs in the tab bar's order and the one showing. A tab is its browser.
  private(set) var tabs: TabList<BrowserViewController>

  let tabBar = TabBarView()
  /// Holds the showing browser's view.
  private let browserContainer = NSView()
  /// The container's top edge, for when the tab bar is showing and when it is not.
  private var topBelowTabBar: NSLayoutConstraint?
  private var topAtPaneTop: NSLayoutConstraint?
  /// Every tab lists through the same reader.
  private let reader: any DirectoryReading
  /// Every tab watches through the same watcher. Nil for a pane whose tabs
  /// watch nothing.
  private let watcher: (any FolderWatching)?
  let pathBar = PathBarView()
  private var rootName = PathCrumbs.defaultRootName
  private var browserBottomAbovePathBar: NSLayoutConstraint?
  private var browserBottomAtPaneBottom: NSLayoutConstraint?
  /// Whether the path bar is shown. Hidden by View > Hide Path Bar.
  public private(set) var showsPathBar = true
  /// Whether AppKit has said the pane's view is on screen.
  private var isOnScreen = false

  /// The browser of the tab that is showing.
  public var showingBrowser: BrowserViewController { tabs.showing }

  /// A pane on the real file system, whose showing tab follows changes made
  /// elsewhere.
  public convenience init(location: URL) {
    self.init(location: location, reader: CompositeReader(), watcher: FolderWatcher())
  }

  /// A pane whose tabs list through `reader`. They watch nothing unless the
  /// pane is also given a watcher.
  public convenience init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil
  ) {
    self.init(location: location, reader: reader, watcher: watcher, restoring: nil)
  }

  /// A pane that opens the tabs of `restoring`, in order, with the saved one
  /// showing. Only the showing tab lists, when its view loads. `location`
  /// is used when there is nothing to restore.
  public init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil,
    restoring: SavedWindow?, resolver: RestoredLocation.Resolver? = nil
  ) {
    self.reader = reader
    self.watcher = watcher
    var browsers: [BrowserViewController] = []
    var showing = 0
    if let saved = restoring, !saved.tabs.isEmpty {
      for tab in saved.tabs {
        // A tab whose location cannot be read is dropped, not shown empty.
        guard let url = URL(string: tab.location) else { continue }
        browsers.append(
          BrowserViewController(
            restoring: tab, location: url, reader: reader, watcher: watcher, resolver: resolver))
      }
      showing = saved.validShowingIndex
    }
    if browsers.isEmpty {
      browsers = [BrowserViewController(location: location, reader: reader, watcher: watcher)]
      showing = 0
    }
    tabs = TabList(tabs: browsers, showingIndex: showing)!
    super.init(nibName: nil, bundle: nil)
    for browser in browsers { adopt(browser) }
    title = tabs.showing.title
    if let saved = restoring, !saved.showsPathBar {
      setPathBarShown(false)
    }
  }

  /// What the pane saves: its tabs, which one shows, and the path bar. The
  /// sidebar's part is filled in by the window's content.
  public func captureState() -> SavedWindow {
    SavedWindow(
      showsPathBar: showsPathBar, tabs: tabs.tabs.map { $0.captureState() },
      showingIndex: tabs.showingIndex)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("PaneViewController is created in code")
  }

  public override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    browserContainer.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(tabBar)
    container.addSubview(browserContainer)
    pathBar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(pathBar)
    pathBar.onNavigate = { [weak self] url in
      guard let self else { return }
      self.showingBrowser.show(url)
      self.showingBrowser.focusList()
    }

    topBelowTabBar = browserContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
    topAtPaneTop = browserContainer.topAnchor.constraint(equalTo: container.topAnchor)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
      browserContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      browserContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      pathBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      pathBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      pathBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      pathBar.heightAnchor.constraint(equalToConstant: PathBarView.height),
    ])
    browserBottomAbovePathBar = browserContainer.bottomAnchor.constraint(
      equalTo: pathBar.topAnchor)
    browserBottomAtPaneBottom = browserContainer.bottomAnchor.constraint(
      equalTo: container.bottomAnchor)
    browserBottomAbovePathBar?.isActive = showsPathBar
    browserBottomAtPaneBottom?.isActive = !showsPathBar
    pathBar.isHidden = !showsPathBar
    view = container
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    tabBar.onAction = { [weak self] in self?.handle($0) }
    showTabs()
    Task { [weak self] in
      let name = await Task.detached { PathCrumbs.startupVolumeName() }.value
      guard let self, let name else { return }
      self.rootName = name
      self.pathBar.update(location: self.showingBrowser.location, rootName: name)
    }
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    // The window does not follow a controller's title once it is on screen.
    updateTitle()
    showingBrowser.focusList()
    view.window?.validateToolbarItems()
    isOnScreen = true
    updateWatching()
  }

  public override func viewDidDisappear() {
    super.viewDidDisappear()
    isOnScreen = false
    updateWatching()
  }

  // MARK: Actions
  //
  // Each command changes the tab list as it arrives and brings the window in
  // line before it returns, so a second command sent straight after sees
  // where the first one left things. Only a browser's listing runs in a task.

  /// Opens a tab at the end of the bar, on the folder the current tab is
  /// showing, and shows it. Sent by File > New Tab and the bar's button.
  @objc public func newTab(_ sender: Any?) {
    // Read as the command arrives: the current tab has already made any move
    // whose listing has yet to start.
    let browser = BrowserViewController(
      location: showingBrowser.location, reader: reader, watcher: watcher)
    adopt(browser)
    tabs.add(browser)
    tabsDidChange()
  }

  /// Closes the showing tab, and the window when it is the last tab. Sent by
  /// File > Close Tab.
  @objc public func closeTab(_ sender: Any?) {
    // The command reaches the main window's pane even while another window,
    // such as the About panel, is the key one: the application tries the main
    // window's responders after the key window's. Command-W closes what is in
    // front, so that window is closed and the tabs are left alone.
    if let keyWindow = NSApplication.shared.keyWindow, keyWindow !== view.window {
      keyWindow.performClose(sender)
      return
    }
    close(showingBrowser)
  }

  /// Shows `location` in the showing tab as a move, or in a new tab. Asked by
  /// the sidebar.
  public func show(_ location: URL, inNewTab: Bool) {
    if inNewTab {
      let browser = BrowserViewController(location: location, reader: reader, watcher: watcher)
      adopt(browser)
      tabs.add(browser)
      tabsDidChange()
    } else {
      showingBrowser.show(location)
    }
  }

  /// Called when the place the showing tab is on changes, and when another
  /// tab starts showing. The sidebar follows it.
  public var onLocationChange: (() -> Void)?

  /// Shows or hides the path bar. Sent by View > Hide Path Bar.
  @objc public func togglePathBar(_ sender: Any?) {
    setPathBarShown(!showsPathBar)
  }

  /// Called when something the pane saves may have changed: a tab, which tab
  /// shows, the path bar, or anything a tab saves.
  public var onStateChange: (() -> Void)?

  private func setPathBarShown(_ shown: Bool) {
    defer { onStateChange?() }
    showsPathBar = shown
    pathBar.isHidden = !shown
    browserBottomAbovePathBar?.isActive = shown
    browserBottomAtPaneBottom?.isActive = !shown
  }

  /// Opens the Go to Folder sheet on the showing tab. Sent by Go > Go to Folder.
  @objc public func goToFolder(_ sender: Any?) {
    guard presentedViewControllers?.isEmpty ?? true else { return }
    let sheet = GoToFolderViewController(base: startingFolderForGoTo)
    sheet.onGo = { [weak self] folder, selecting in
      guard let self else { return }
      self.showingBrowser.show(folder, selecting: selecting)
      self.showingBrowser.focusList()
    }
    presentAsSheet(sheet)
  }

  /// The folder the sheet starts on: the one showing, or home for a tag or
  /// the recents.
  private var startingFolderForGoTo: URL {
    let location = showingBrowser.location
    return VirtualLocation.isVirtual(location)
      ? FileManager.default.homeDirectoryForCurrentUser : location
  }

  /// Shows the tab to the right, wrapping around. Sent by Window > Show Next Tab.
  @objc public func showNextTab(_ sender: Any?) {
    guard tabs.showNext() else { return }
    tabsDidChange()
  }

  /// Shows the tab to the left, wrapping around. Sent by Window > Show Previous Tab.
  @objc public func showPreviousTab(_ sender: Any?) {
    guard tabs.showPrevious() else { return }
    tabsDidChange()
  }

  /// What a press in the tab bar asks for.
  private func handle(_ action: TabBarView.Action) {
    switch action {
    case .show(let id):
      guard let browser = id.base as? BrowserViewController, tabs.show(browser) else { return }
      tabsDidChange()
    case .close(let id):
      guard let browser = id.base as? BrowserViewController else { return }
      close(browser)
    case .new:
      newTab(nil)
    }
  }

  private func close(_ browser: BrowserViewController) {
    switch tabs.close(browser) {
    case .unchanged:
      return
    case .lastTab:
      // The tab stays; the window goes, and may refuse.
      view.window?.performClose(nil)
    case .closed:
      browser.cancelLoad()
      browser.stopWatching()
      browser.onTitleChange = nil
      browser.onLocationChange = nil
      browser.onStateChange = nil
      if browser.isViewLoaded {
        browser.view.removeFromSuperview()
      }
      browser.removeFromParent()
      tabsDidChange()
    }
  }

  // MARK: Drawing the tabs

  /// Makes a browser a tab of this pane. Its view joins the window only
  /// while its tab is showing.
  private func adopt(_ browser: BrowserViewController) {
    addChild(browser)
    browser.onStateChange = { [weak self] in self?.onStateChange?() }
    browser.onTitleChange = { [weak self, weak browser] in
      guard let self, let browser else { return }
      self.updateTabBar()
      if browser === self.showingBrowser {
        self.updateTitle()
      }
    }
    browser.onLocationChange = { [weak self, weak browser] in
      guard let self, let browser, browser === self.showingBrowser else { return }
      self.locationChanged()
    }
  }

  /// What every command that changed the tab list ends with: the window is
  /// brought in line, then keyboard focus, in that order, because focus goes
  /// to a view that has to be in the window first.
  private func tabsDidChange() {
    onStateChange?()
    showTabs()
    restoreFocus()
  }

  /// Brings the window in line with the tab list: the showing browser's view,
  /// the tab bar, the title and the toolbar.
  private func showTabs() {
    let browser = showingBrowser
    if browser.view.superview !== browserContainer {
      for subview in browserContainer.subviews {
        subview.removeFromSuperview()
      }
      browser.view.translatesAutoresizingMaskIntoConstraints = false
      browserContainer.addSubview(browser.view)
      NSLayoutConstraint.activate([
        browser.view.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
        browser.view.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),
        browser.view.topAnchor.constraint(equalTo: browserContainer.topAnchor),
        browser.view.bottomAnchor.constraint(equalTo: browserContainer.bottomAnchor),
      ])
    }
    updateTabBar()
    updateTitle()
    view.window?.validateToolbarItems()
    updateWatching()
    locationChanged()
  }

  /// The showing tab is somewhere else, or another tab is showing: the path
  /// bar follows, then the owner.
  private func locationChanged() {
    pathBar.update(location: showingBrowser.location, rootName: rootName)
    onLocationChange?()
  }

  /// Brings the browsers in line with who should be watching: the showing
  /// tab while the pane is on screen, and no other. Only the pane knows
  /// which tab is showing, as with the window's title and keyboard focus.
  private func updateWatching() {
    for browser in tabs.tabs where browser !== showingBrowser {
      browser.stopWatching()
    }
    if isOnScreen {
      showingBrowser.startWatching()
    } else {
      showingBrowser.stopWatching()
    }
  }

  /// Redraws the tab bar, which is hidden while there is one tab.
  private func updateTabBar() {
    tabBar.update(
      tabs: tabs.tabs.map { TabBarView.Tab(id: $0, title: $0.title ?? "") },
      showing: showingBrowser)
    let showsBar = tabs.tabs.count > 1
    tabBar.isHidden = !showsBar
    topAtPaneTop?.isActive = !showsBar
    topBelowTabBar?.isActive = showsBar
  }

  /// Names the pane and its window after the showing tab's folder. The window
  /// is set directly because it does not follow a title that changes after
  /// it opens.
  private func updateTitle() {
    title = showingBrowser.title
    view.window?.title = title ?? ""
  }

  /// Puts keyboard focus in the showing tab's file list after the tabs
  /// changed, unless it is on a tab bar control that is still there. When the
  /// view that had focus leaves the window, the window is left as its own
  /// first responder, with focus on nothing.
  private func restoreFocus() {
    if !tabBar.isHidden, let focused = view.window?.firstResponder as? NSView,
      focused.isDescendant(of: tabBar)
    {
      return
    }
    showingBrowser.focusList()
  }

  // MARK: The responder chain

  /// Offers the showing browser for an action it handles. With keyboard focus
  /// in the file list the chain passes the browser before it reaches the
  /// pane. With focus on a control in the tab bar it reaches the pane without
  /// passing a browser, and Back, Forward, Enclosing Folder and Open would
  /// reach no one. A toolbar button that has focus asks the pane itself.
  public override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
    if showingBrowser.responds(to: action) {
      return showingBrowser
    }
    return super.supplementalTarget(forAction: action, sender: sender)
  }
}

extension PaneViewController: NSUserInterfaceValidations {
  /// Enables the tab commands only when they can do something.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)):
      return tabs.tabs.count > 1
    case #selector(togglePathBar(_:)):
      (item as? NSMenuItem)?.title = showsPathBar ? "Hide Path Bar" : "Show Path Bar"
      return true
    default:
      return true
    }
  }
}
