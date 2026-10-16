import AppKit
import FileSystemCore

/// The window's content: the sidebar to the left of the pane.
///
/// A window's commands reach the showing browser through the pane, which is
/// a child of this controller, not an ancestor of the sidebar. With keyboard
/// focus in the sidebar the chain reaches this controller and no further, so
/// it offers the pane (and through it the showing browser) for the actions
/// they handle, as the pane does for its own tab bar.
@MainActor
public final class WindowContentViewController: NSSplitViewController {
  public let sidebar: SidebarViewController
  public let pane: PaneViewController

  /// A window on the real file system.
  public convenience init(location: URL) {
    self.init(pane: PaneViewController(location: location), sidebar: SidebarViewController())
  }

  public init(pane: PaneViewController, sidebar: SidebarViewController) {
    self.pane = pane
    self.sidebar = sidebar
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("WindowContentViewController is created in code")
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    splitView.isVertical = true
    splitView.dividerStyle = .thin

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
    sidebarItem.minimumThickness = 150
    sidebarItem.maximumThickness = 320
    sidebarItem.canCollapse = true
    sidebarItem.preferredThicknessFraction = 0.18
    addSplitViewItem(sidebarItem)

    let paneItem = NSSplitViewItem(viewController: pane)
    paneItem.minimumThickness = 400
    addSplitViewItem(paneItem)

    sidebar.onChoose = { [weak self] item, inNewTab in
      self?.pane.show(item.location, inNewTab: inNewTab)
    }
    pane.onLocationChange = { [weak self] in
      guard let self else { return }
      self.sidebar.select(location: self.pane.showingBrowser.location)
    }
    sidebar.select(location: pane.showingBrowser.location)
    pane.onStateChange = { [weak self] in self?.onStateChange?() }
  }

  /// Called when something the window saves may have changed. The owner
  /// connects a ``StateSaver`` to it.
  public var onStateChange: (() -> Void)?

  /// What the window saves: the pane's tabs and the sidebar's width and
  /// whether it is collapsed.
  public func captureState() -> SavedWindow {
    var saved = pane.captureState()
    if let item = splitViewItems.first, isViewLoaded {
      saved.sidebarCollapsed = item.isCollapsed
      // A collapsed sidebar has no width worth keeping.
      let width = sidebar.view.frame.width
      saved.sidebarWidth = item.isCollapsed || width <= 0 ? nil : Double(width)
    }
    return saved
  }

  public override func splitViewDidResizeSubviews(_ notification: Notification) {
    super.splitViewDidResizeSubviews(notification)
    onStateChange?()
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    // The sidebar is first in the key view loop, and a window gives its
    // first key view the focus when it has none. Keyboard use starts in the
    // list, as it did before there was a sidebar.
    pane.showingBrowser.focusList()
  }

  /// Adds the selected folder, or the one being shown, to Favorites. Sent
  /// by File > Add to Sidebar.
  @objc public func addToSidebar(_ sender: Any?) {
    guard let folder = pane.showingBrowser.folderToAdd else { return }
    let sidebar = sidebar
    Task { await sidebar.addFavorite(folder) }
  }

  public override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
    if pane.responds(to: action) { return pane }
    if let target = pane.supplementalTarget(forAction: action, sender: sender) { return target }
    return super.supplementalTarget(forAction: action, sender: sender)
  }

  public override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(addToSidebar(_:)) {
      return pane.showingBrowser.folderToAdd != nil
    }
    return super.validateUserInterfaceItem(item)
  }
}
