import Testing

@testable import BrowserUI

@Suite struct TabListTests {
  /// Tabs a, b and c, with the named one showing.
  private func abc(showing tab: String) throws -> TabList<String> {
    let index = try #require(["a", "b", "c"].firstIndex(of: tab))
    return try #require(TabList(tabs: ["a", "b", "c"], showingIndex: index))
  }

  @Test func aNewListHasOneTabAndItIsShowing() {
    let list = TabList("a")
    #expect(list.tabs == ["a"])
    #expect(list.showing == "a")
    #expect(list.showingIndex == 0)
  }

  @Test func addingATabPutsItLastAndShowsIt() throws {
    var list = try #require(TabList(tabs: ["a", "b"], showingIndex: 0))
    list.add("c")
    #expect(list.tabs == ["a", "b", "c"])
    #expect(list.showing == "c")

    // A tab appears once: adding one that is already there only shows it.
    list.add("a")
    #expect(list.tabs == ["a", "b", "c"])
    #expect(list.showing == "a")
  }

  @Test func aListBuiltWithAPositionOutOfRangeShowsTheNearestTab() throws {
    #expect(try #require(TabList(tabs: ["a", "b", "c"], showingIndex: 1)).showing == "b")
    #expect(try #require(TabList(tabs: ["a", "b", "c"], showingIndex: 7)).showing == "c")
    #expect(try #require(TabList(tabs: ["a", "b", "c"], showingIndex: -2)).showing == "a")
    // A pane always has a tab, so there is no empty list.
    #expect(TabList(tabs: [String](), showingIndex: 0) == nil)
  }

  @Test func closingTheShowingTabShowsItsRightNeighbourElseItsLeft() throws {
    var middle = try abc(showing: "b")
    #expect(middle.close("b") == .closed(showingChanged: true))
    #expect(middle.tabs == ["a", "c"])
    #expect(middle.showing == "c")

    var last = try abc(showing: "c")
    #expect(last.close("c") == .closed(showingChanged: true))
    #expect(last.tabs == ["a", "b"])
    #expect(last.showing == "b")
  }

  @Test func closingATabThatIsNotShowingLeavesTheShowingTabAlone() throws {
    var lastShowing = try abc(showing: "c")
    #expect(lastShowing.close("a") == .closed(showingChanged: false))
    #expect(lastShowing.tabs == ["b", "c"])
    #expect(lastShowing.showing == "c")

    var firstShowing = try abc(showing: "a")
    #expect(firstShowing.close("c") == .closed(showingChanged: false))
    #expect(firstShowing.tabs == ["a", "b"])
    #expect(firstShowing.showing == "a")
  }

  @Test func closingTheOnlyTabReportsTheLastTabAndKeepsIt() {
    var list = TabList("a")
    #expect(list.close("a") == .lastTab)
    #expect(list.tabs == ["a"])
    #expect(list.showing == "a")
  }

  @Test func nextAndPreviousWrapAroundAtTheEnds() throws {
    var list = try abc(showing: "c")
    #expect(list.showNext() == true)
    #expect(list.showing == "a")
    #expect(list.showPrevious() == true)
    #expect(list.showing == "c")
    #expect(list.showPrevious() == true)
    #expect(list.showing == "b")
    #expect(list.showNext() == true)
    #expect(list.showing == "c")
    #expect(list.tabs == ["a", "b", "c"])
  }

  @Test func withOneTabNextAndPreviousReportNoChange() {
    var list = TabList("a")
    #expect(list.showNext() == false)
    #expect(list.showPrevious() == false)
    #expect(list.showing == "a")
  }

  @Test func showingATabByIdentity() throws {
    var list = try abc(showing: "a")
    #expect(list.show("c") == true)
    #expect(list.showing == "c")
    // The tab already showing, and a tab that is not in the list.
    #expect(list.show("c") == false)
    #expect(list.show("z") == false)
    #expect(list.showing == "c")
  }

  @Test func closingAnUnknownTabReportsNoChange() throws {
    var list = try abc(showing: "b")
    let before = list
    #expect(list.close("z") == .unchanged)
    #expect(list == before)
  }
}
