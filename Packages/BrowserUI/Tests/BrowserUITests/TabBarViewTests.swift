import AppKit
import Testing

@testable import BrowserUI

@Suite @MainActor struct TabBarViewTests {
  /// A bar showing the given titles, identified by their positions, with the
  /// tab at `showing` showing.
  private func bar(_ titles: [String], showing: Int) -> TabBarView {
    let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
    bar.update(tabs: Self.tabs(titles), showing: showing)
    bar.layoutSubtreeIfNeeded()
    return bar
  }

  private static func tabs(_ titles: [String]) -> [TabBarView.Tab] {
    titles.enumerated().map { TabBarView.Tab(id: $0.offset, title: $0.element) }
  }

  /// The bar's buttons that carry an element's identifier, in view order.
  private func buttons(_ element: AccessibilityElement, in bar: TabBarView) -> [NSButton] {
    var found: [NSButton] = []
    func visit(_ view: NSView) {
      if let button = view as? NSButton, button.accessibilityIdentifier() == element.identifier {
        found.append(button)
      }
      for subview in view.subviews { visit(subview) }
    }
    visit(bar)
    return found
  }

  @Test func theBarIsAnIdentifiedLabelledTabGroup() {
    let bar = bar(["Documents"], showing: 0)
    #expect(bar.accessibilityIdentifier() == "tab-bar")
    #expect(bar.accessibilityLabel() == "Tabs")
    #expect(bar.isAccessibilityElement())
    #expect(bar.accessibilityRole() == .tabGroup)
  }

  @Test func holdsOneTabButtonPerTabInOrderSpeakingItsOwnTitle() {
    let bar = bar(["Documents", "Sub", "Sub"], showing: 1)
    let tabs = buttons(.tab, in: bar)
    #expect(tabs.map(\.title) == ["Documents", "Sub", "Sub"])
    #expect(tabs.map { $0.accessibilityTitle() } == ["Documents", "Sub", "Sub"])
    // No fixed label stands in front of the title.
    #expect(tabs.allSatisfy { $0.accessibilityLabel() != AccessibilityElement.tab.label })
    // Left to right, as the list is ordered.
    let positions = tabs.map { $0.convert($0.bounds, to: bar).minX }
    #expect(positions == positions.sorted() && Set(positions).count == 3)
  }

  @Test func onlyTheShowingTabReportsItselfSelected() {
    let bar = bar(["Documents", "Sub", "Sub"], showing: 1)
    let tabs = buttons(.tab, in: bar)
    #expect(tabs.map { $0.isAccessibilitySelected() } == [false, true, false])
    #expect(tabs.map { $0.accessibilityValue() as? Int } == [0, 1, 0])
    for tab in tabs {
      #expect(tab.accessibilityRole() == .radioButton)
      #expect(tab.accessibilitySubrole() == .tabButtonSubrole)
    }
  }

  @Test func theShowingTabIsMarkedByMoreThanColor() throws {
    let bar = bar(["Documents", "Sub"], showing: 1)
    let tabs = buttons(.tab, in: bar)
    try #require(tabs.count == 2)
    let fonts = tabs.map {
      $0.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    }
    let (other, showing) = (try #require(fonts[0]), try #require(fonts[1]))
    #expect(NSFontManager.shared.weight(of: showing) > NSFontManager.shared.weight(of: other))
  }

  @Test func tabTitlesUseThePrimaryLabelColorWhetherShowingOrNot() throws {
    let bar = bar(["Documents", "Sub"], showing: 1)
    let tabs = buttons(.tab, in: bar)
    try #require(tabs.count == 2)
    for tab in tabs {
      let title = tab.attributedTitle
      var range = NSRange()
      let color = title.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
      #expect(color == .labelColor)
      #expect(range == NSRange(location: 0, length: title.length))
    }
  }

  @Test func eachTabHasACloseButtonThatSaysWhichTabItCloses() {
    let bar = bar(["Documents", "Sub", "Sub"], showing: 1)
    let closeButtons = buttons(.closeTabButton, in: bar)
    #expect(
      closeButtons.map { $0.accessibilityLabel() }
        == ["Close Tab Documents", "Close Tab Sub", "Close Tab Sub"])
    // A real button beside its tab, not inside it.
    let tabs = buttons(.tab, in: bar)
    for (close, tab) in zip(closeButtons, tabs) {
      #expect(close.superview === tab.superview)
      #expect(!close.frame.intersects(tab.frame))
    }
  }

  @Test func theNewTabButtonHasItsDeclaredIdentifierAndLabel() throws {
    let bar = bar(["Documents"], showing: 0)
    let newTab = buttons(.newTabButton, in: bar)
    try #require(newTab.count == 1)
    #expect(newTab[0].accessibilityLabel() == "New Tab")
  }

  @Test func aTabTitledWithASlashShowsAndSpeaksIt() throws {
    let bar = bar(["/"], showing: 0)
    let tab = try #require(buttons(.tab, in: bar).first)
    #expect(tab.title == "/")
    #expect(tab.accessibilityTitle() == "/")
    #expect(buttons(.closeTabButton, in: bar).first?.accessibilityLabel() == "Close Tab /")
  }

  @Test func aTitleTooLongToFitIsStillSpokenInFull() throws {
    let long = String(repeating: "A very long folder name ", count: 20)
    let bar = bar([long, "Sub"], showing: 0)
    let tab = try #require(buttons(.tab, in: bar).first)
    try #require(tab.frame.width < tab.attributedTitle.size().width)
    // The bar keeps its width: the title is cut short on screen instead.
    #expect(bar.frame.width == 600)
    #expect(tab.frame.width > 0)
    #expect(tab.accessibilityTitle() == long)
  }

  @Test func anUpdateChangesTheExistingControlsInPlace() {
    let bar = bar(["Documents", "Sub", "Sub"], showing: 1)
    let tabsBefore = buttons(.tab, in: bar)
    let closeBefore = buttons(.closeTabButton, in: bar)

    bar.update(tabs: Self.tabs(["Renamed", "Sub", "Sub"]), showing: 2)
    let tabs = buttons(.tab, in: bar)
    #expect(tabs.count == 3)
    #expect(zip(tabs, tabsBefore).allSatisfy { $0 === $1 })
    #expect(zip(buttons(.closeTabButton, in: bar), closeBefore).allSatisfy { $0 === $1 })
    #expect(tabs.map(\.title) == ["Renamed", "Sub", "Sub"])
    #expect(tabs.map { $0.isAccessibilitySelected() } == [false, false, true])
    #expect(closeBefore.first?.accessibilityLabel() == "Close Tab Renamed")
  }

  @Test func anUpdateThatRemovesATabKeepsTheOthersControls() throws {
    let bar = bar(["Documents", "Sub", "Other"], showing: 0)
    let before = buttons(.tab, in: bar)
    try #require(before.count == 3)

    bar.update(
      tabs: [TabBarView.Tab(id: 0, title: "Documents"), TabBarView.Tab(id: 2, title: "Other")],
      showing: 0)
    let after = buttons(.tab, in: bar)
    try #require(after.count == 2)
    #expect(after[0] === before[0])
    #expect(after[1] === before[2])
    #expect(before[1].window == nil && before[1].superview?.superview == nil)
    #expect(buttons(.closeTabButton, in: bar).count == 2)
  }

  @Test func anUpdateThatAddsATabPutsItsControlsLast() throws {
    let bar = bar(["Documents"], showing: 0)
    let first = try #require(buttons(.tab, in: bar).first)

    bar.update(tabs: Self.tabs(["Documents", "Sub"]), showing: 1)
    bar.layoutSubtreeIfNeeded()
    let tabs = buttons(.tab, in: bar)
    try #require(tabs.count == 2)
    #expect(tabs[0] === first)
    #expect(tabs[1].title == "Sub")
    #expect(
      tabs[0].convert(tabs[0].bounds, to: bar).minX < tabs[1].convert(tabs[1].bounds, to: bar).minX)
  }

  @Test func pressingAControlReportsWhatWasAskedFor() throws {
    let bar = bar(["Documents", "Sub"], showing: 0)
    var actions: [TabBarView.Action] = []
    bar.onAction = { actions.append($0) }

    try #require(buttons(.tab, in: bar).count == 2)
    buttons(.tab, in: bar)[1].performClick(nil)
    buttons(.closeTabButton, in: bar)[0].performClick(nil)
    try #require(buttons(.newTabButton, in: bar).first).performClick(nil)
    #expect(actions == [.show(1), .close(0), .new])
  }

  @Test func theBarUsesDeclaredElementsForEveryControl() {
    let bar = bar(["Documents", "Sub"], showing: 0)
    let declared = Set(AccessibilityElement.all.map(\.identifier))
    var found: [String] = []
    var unidentified: [NSButton] = []
    func visit(_ view: NSView) {
      let identifier = view.accessibilityIdentifier()
      if !identifier.isEmpty { found.append(identifier) }
      if let button = view as? NSButton, identifier.isEmpty { unidentified.append(button) }
      for subview in view.subviews { visit(subview) }
    }
    visit(bar)

    #expect(
      found.filter { !$0.hasPrefix("_") }.sorted() == [
        "close-tab", "close-tab", "new-tab", "tab", "tab", "tab-bar",
      ])
    for identifier in found where !identifier.hasPrefix("_") {
      #expect(
        declared.contains(identifier), "\(identifier) is not declared in AccessibilityElement")
    }
    #expect(unidentified.isEmpty)
  }
}
