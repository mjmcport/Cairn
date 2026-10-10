/// The tabs of one pane: their order and which one is showing.
///
/// A tab is whatever identifies it to the owner. A pane always has at least
/// one tab, so the list is never empty. Every change is synchronous and
/// reports what it did, so a command can act on the answer as it arrives.
public struct TabList<Tab: Hashable>: Equatable {
  /// What ``close(_:)`` did.
  public enum Closing: Sendable, Equatable {
    /// The tab is not in the list.
    case unchanged
    /// The tab is the only one. It stays; the owner closes the window.
    case lastTab
    /// The tab was removed.
    /// - Parameter showingChanged: Whether another tab is showing now.
    case closed(showingChanged: Bool)
  }

  /// The tabs in the order the tab bar shows them. Each appears once.
  public private(set) var tabs: [Tab]
  /// The position of the showing tab in ``tabs``.
  public private(set) var showingIndex: Int

  /// The tab being shown.
  public var showing: Tab { tabs[showingIndex] }

  /// A list of one tab.
  public init(_ tab: Tab) {
    tabs = [tab]
    showingIndex = 0
  }

  /// A list of several tabs, or `nil` when there are none.
  /// - Parameter showingIndex: A position out of range falls back to the
  ///   nearest tab.
  public init?(tabs: [Tab], showingIndex: Int) {
    guard !tabs.isEmpty else { return nil }
    self.tabs = tabs
    self.showingIndex = min(max(showingIndex, 0), tabs.count - 1)
  }

  /// Adds a tab at the end and shows it. A tab already in the list is left
  /// where it is and shown.
  public mutating func add(_ tab: Tab) {
    if !tabs.contains(tab) {
      tabs.append(tab)
    }
    show(tab)
  }

  /// Removes a tab. When it was showing, the tab to its right is shown, or
  /// the tab to its left when there is none to the right.
  public mutating func close(_ tab: Tab) -> Closing {
    guard let index = tabs.firstIndex(of: tab) else { return .unchanged }
    guard tabs.count > 1 else { return .lastTab }
    let wasShowing = index == showingIndex
    tabs.remove(at: index)
    if index < showingIndex {
      // The showing tab moved one place left with the tabs after the gap.
      showingIndex -= 1
    } else if wasShowing {
      // The right neighbour now sits at `index`, unless the last tab closed.
      showingIndex = min(index, tabs.count - 1)
    }
    return .closed(showingChanged: wasShowing)
  }

  /// Shows a tab.
  /// - Returns: Whether the showing tab changed. It does not for the tab
  ///   already showing or a tab that is not in the list.
  @discardableResult
  public mutating func show(_ tab: Tab) -> Bool {
    guard let index = tabs.firstIndex(of: tab), index != showingIndex else { return false }
    showingIndex = index
    return true
  }

  /// Shows the tab to the right, or the first tab from the last.
  /// - Returns: Whether the showing tab changed. It does not with one tab.
  @discardableResult
  public mutating func showNext() -> Bool {
    step(by: 1)
  }

  /// Shows the tab to the left, or the last tab from the first.
  /// - Returns: Whether the showing tab changed. It does not with one tab.
  @discardableResult
  public mutating func showPrevious() -> Bool {
    step(by: -1)
  }

  private mutating func step(by offset: Int) -> Bool {
    guard tabs.count > 1 else { return false }
    showingIndex = (showingIndex + offset + tabs.count) % tabs.count
    return true
  }
}

// A pane's tabs are its browsers, which belong to the main actor and are not
// sendable; a list of plain values is.
extension TabList: Sendable where Tab: Sendable {}
