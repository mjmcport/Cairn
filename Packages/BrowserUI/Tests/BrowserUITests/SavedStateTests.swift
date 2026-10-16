import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

@Suite struct SavedStateTests {
  private func sample() -> SavedState {
    let tab = SavedTab(
      location: "file:///Users/x/Docs/",
      viewMode: .columns,
      sort: SavedSort(key: .modificationDate, ascending: false, foldersFirst: true),
      showsHidden: true,
      openFolders: [["a"], ["a", "b"]],
      selection: ["file:///Users/x/Docs/a/f.txt"],
      back: [SavedHistoryEntry(location: "file:///Users/x/", selection: ["file:///Users/x/Docs/"])],
      forward: [])
    let tag = SavedTab(location: "cairn-tag:Red")
    return SavedState(
      windows: [
        SavedWindow(
          sidebarWidth: 210, sidebarCollapsed: true, showsPathBar: false, tabs: [tab, tag],
          showingIndex: 1)
      ])
  }

  @Test func roundTrips() throws {
    let state = sample()
    let data = try #require(state.encoded())
    #expect(SavedState.decode(data) == state)
  }

  @Test func virtualLocationSurvives() throws {
    let data = try #require(sample().encoded())
    let decoded = try #require(SavedState.decode(data))
    #expect(decoded.windows[0].tabs[1].location == "cairn-tag:Red")
  }

  @Test func unknownVersionIsIgnored() throws {
    var state = sample()
    state.version = SavedState.currentVersion + 1
    let data = try #require(state.encoded())
    #expect(SavedState.decode(data) == nil)
  }

  @Test func damagedDataIsIgnored() {
    #expect(SavedState.decode(Data("not json".utf8)) == nil)
    #expect(SavedState.decode(Data("{\"version\":1}".utf8)) == nil)
    #expect(SavedState.decode(Data()) == nil)
  }

  @Test func historyIsLimitedToTheNearestEntries() {
    let entries = (0..<30).map { SavedHistoryEntry(location: "file:///\($0)/") }
    let tab = SavedTab(location: "file:///", back: entries, forward: entries)
    #expect(tab.back.count == SavedTab.historyLimit)
    #expect(tab.back.first?.location == "file:///10/")
    #expect(tab.back.last?.location == "file:///29/")
    #expect(tab.forward.first?.location == "file:///0/")
    #expect(tab.forward.count == SavedTab.historyLimit)
  }

  @Test func showingIndexIsClamped() {
    let tabs = [SavedTab(location: "a"), SavedTab(location: "b")]
    #expect(SavedWindow(tabs: tabs, showingIndex: 9).validShowingIndex == 1)
    #expect(SavedWindow(tabs: tabs, showingIndex: -3).validShowingIndex == 0)
    #expect(SavedWindow(tabs: [], showingIndex: 4).validShowingIndex == 0)
  }

  @Test func sortAndModeConvertBothWays() {
    for key: FileItemSort.Key in [.name, .size, .sizeOnDisk, .modificationDate, .dateAdded] {
      let sort = FileItemSort(key: key, ascending: false, foldersFirst: true)
      #expect(SavedSort(sort).fileItemSort == sort)
    }
    for mode: BrowserModel.ViewMode in [.list, .icons, .columns] {
      #expect(SavedViewMode(mode).browserMode == mode)
    }
  }

  @Test func storeSavesLoadsAndClears() throws {
    let name = "SavedStateTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = UserDefaultsStateStore(defaults: defaults)
    #expect(store.load() == nil)
    store.save(Data("x".utf8))
    #expect(store.load() == Data("x".utf8))
    store.clear()
    #expect(store.load() == nil)
  }

  @Test func launchStoreUsesTheNamedSuite() throws {
    let argName = "SavedStateTests-arg-\(UUID().uuidString)"
    let suiteName = "SavedStateTests-suite-\(UUID().uuidString)"
    let args = try #require(UserDefaults(suiteName: argName))
    defer {
      args.removePersistentDomain(forName: argName)
      UserDefaults().removePersistentDomain(forName: suiteName)
    }
    args.set(suiteName, forKey: UserDefaultsStateStore.suiteArgument)
    UserDefaultsStateStore.forLaunch(defaults: args).save(Data("y".utf8))
    let suite = try #require(UserDefaults(suiteName: suiteName))
    #expect(suite.data(forKey: UserDefaultsStateStore.key) == Data("y".utf8))
    #expect(args.data(forKey: UserDefaultsStateStore.key) == nil)
  }
}
