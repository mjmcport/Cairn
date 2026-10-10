import AppKit

/// The row of tabs above a pane's file list, with a close button beside each
/// tab and a New Tab button at the trailing end.
///
/// The bar knows nothing about browsers. Its owner gives it the tabs to show
/// and hears what was pressed through ``onAction``; nothing changes on screen
/// until the owner calls ``update(tabs:showing:)`` again.
///
/// Every control is a real button, so Full Keyboard Access and VoiceOver
/// reach each tab and each close button. Tabs share the bar's width. Below
/// ``minimumTabWidth`` each, the rightmost are cut off at the New Tab button
/// and stay reachable from the keyboard.
@MainActor
final class TabBarView: NSView {
  /// One tab as the bar shows it.
  struct Tab: Equatable {
    /// Whatever tells the owner's tabs apart.
    let id: AnyHashable
    let title: String
  }

  /// What a press on one of the bar's controls asks for.
  enum Action: Equatable {
    case show(AnyHashable)
    case close(AnyHashable)
    case new
  }

  static let height: CGFloat = 30
  static let minimumTabWidth: CGFloat = 80

  var onAction: ((Action) -> Void)?

  /// One view per tab, in order.
  private var items: [TabItemView] = []
  private let tabStack = NSStackView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    apply(.tabBar)

    tabStack.orientation = .horizontal
    tabStack.distribution = .fillEqually
    tabStack.spacing = 2
    tabStack.translatesAutoresizingMaskIntoConstraints = false
    // Cuts off the tabs that do not fit, so they cannot cover the New Tab button.
    let clip = NSView()
    clip.clipsToBounds = true
    clip.translatesAutoresizingMaskIntoConstraints = false
    clip.addSubview(tabStack)

    let newTab = Self.symbolButton("plus", for: .newTabButton)
    newTab.apply(.newTabButton)
    newTab.toolTip = "Open a new tab"
    newTab.target = self
    newTab.action = #selector(newTabPressed(_:))

    addSubview(clip)
    addSubview(newTab)
    // The tabs fill the space when they can. Below the window-resizing
    // priorities, so too many tabs overflow the clip and never widen the window.
    let fill = tabStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor)
    fill.priority = .dragThatCannotResizeWindow
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      clip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      clip.topAnchor.constraint(equalTo: topAnchor),
      clip.bottomAnchor.constraint(equalTo: bottomAnchor),
      clip.trailingAnchor.constraint(equalTo: newTab.leadingAnchor, constant: -4),
      newTab.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      newTab.centerYAnchor.constraint(equalTo: centerYAnchor),
      newTab.widthAnchor.constraint(equalToConstant: TabItemView.buttonSize),
      newTab.heightAnchor.constraint(equalToConstant: TabItemView.buttonSize),
      tabStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
      tabStack.topAnchor.constraint(equalTo: clip.topAnchor),
      tabStack.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
      fill,
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TabBarView is created in code")
  }

  /// Shows these tabs. A tab that was already shown keeps its controls, so a
  /// control that has keyboard focus keeps it; controls are only made for a
  /// tab that is new and removed for one that is gone.
  func update(tabs: [Tab], showing: AnyHashable) {
    let previous = items
    items = tabs.map { tab in
      let item = previous.first { $0.id == tab.id } ?? makeItem(id: tab.id)
      item.show(title: tab.title, isShowing: tab.id == showing)
      return item
    }
    for item in previous where !items.contains(where: { $0 === item }) {
      tabStack.removeView(item)
    }
    for (index, item) in items.enumerated() where item.superview == nil {
      tabStack.insertArrangedSubview(item, at: index)
    }
  }

  private func makeItem(id: AnyHashable) -> TabItemView {
    let item = TabItemView(id: id)
    item.tabButton.target = self
    item.tabButton.action = #selector(tabPressed(_:))
    item.closeButton.target = self
    item.closeButton.action = #selector(closePressed(_:))
    return item
  }

  @objc private func tabPressed(_ sender: NSView) {
    guard let item = sender.superview as? TabItemView else { return }
    onAction?(.show(item.id))
  }

  @objc private func closePressed(_ sender: NSView) {
    guard let item = sender.superview as? TabItemView else { return }
    onAction?(.close(item.id))
  }

  @objc private func newTabPressed(_ sender: Any?) {
    onAction?(.new)
  }

  /// A small button that shows only a symbol. The caller gives it its
  /// identity; `element` names the symbol for a reader of the image.
  fileprivate static func symbolButton(_ symbolName: String, for element: AccessibilityElement)
    -> NSButton
  {
    let button = NSButton(title: element.label, target: nil, action: nil)
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: element.label)
    // Without the symbol the button falls back to showing its title.
    button.imagePosition = button.image == nil ? .noImage : .imageOnly
    button.isBordered = false
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  // MARK: Accessibility

  override func isAccessibilityElement() -> Bool { true }

  override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }

  override func draw(_ dirtyRect: NSRect) {
    // A line between the bar and the file list.
    NSColor.separatorColor.setFill()
    NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
  }
}

/// One tab in the bar: its close button and, beside it, the tab itself. The
/// view draws the shape that marks the showing tab around both.
private final class TabItemView: NSView {
  static let buttonSize: CGFloat = 20

  let id: AnyHashable
  let tabButton = TabButton(title: "", target: nil, action: nil)
  let closeButton = TabBarView.symbolButton("xmark", for: .closeTabButton)

  init(id: AnyHashable) {
    self.id = id
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    tabButton.applyIdentifier(of: .tab)
    tabButton.isBordered = false
    tabButton.translatesAutoresizingMaskIntoConstraints = false
    // A long title is cut short; it must not push the other tabs out.
    tabButton.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    tabButton.setContentHuggingPriority(.init(1), for: .horizontal)
    closeButton.toolTip = "Close this tab"

    addSubview(closeButton)
    addSubview(tabButton)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(greaterThanOrEqualToConstant: TabBarView.minimumTabWidth),
      closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
      closeButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
      tabButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 2),
      tabButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      tabButton.topAnchor.constraint(equalTo: topAnchor),
      tabButton.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TabItemView is created in code")
  }

  func show(title: String, isShowing: Bool) {
    tabButton.show(title: title, isShowing: isShowing)
    // The close button says which tab it closes.
    closeButton.apply(.closeTabButton, for: title)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard tabButton.isShowing else { return }
    NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 3), xRadius: 5, yRadius: 5).fill()
  }
}

/// A tab: a button that VoiceOver hears as a tab, selected or not. It speaks
/// its title, the folder's name, so it takes an identifier and no label.
final class TabButton: NSButton {
  private(set) var isShowing = false

  /// The showing tab is marked by its weight and by the shape its item draws
  /// behind it, not by color: the title is the primary label color in every
  /// state, because a dimmer one fails the contrast audit.
  func show(title: String, isShowing: Bool) {
    self.isShowing = isShowing
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    paragraph.alignment = .center
    attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: NSColor.labelColor,
        .font: NSFont.systemFont(
          ofSize: NSFont.systemFontSize, weight: isShowing ? .semibold : .regular),
        .paragraphStyle: paragraph,
      ])
  }

  override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }

  override func accessibilitySubrole() -> NSAccessibility.Subrole? { .tabButtonSubrole }

  override func accessibilityValue() -> Any? { isShowing ? 1 : 0 }

  override func isAccessibilitySelected() -> Bool { isShowing }
}
