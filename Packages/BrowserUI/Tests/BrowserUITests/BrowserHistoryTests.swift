import FileSystemCore
import Foundation
import TestSupport
import Testing

@testable import BrowserUI

@Suite struct BrowserHistoryTests {
  private let a = URL(filePath: "/a", directoryHint: .isDirectory)
  private let b = URL(filePath: "/a/b", directoryHint: .isDirectory)
  private let c = URL(filePath: "/a/b/c", directoryHint: .isDirectory)
  private let file = URL(filePath: "/a/b/file.txt")

  @Test func startsWithNowhereToGo() {
    var history = BrowserHistory(current: a)
    #expect(history.current == a)
    #expect(!history.canGoBack)
    #expect(!history.canGoForward)
    #expect(history.goBack() == nil)
    #expect(history.goForward() == nil)
    #expect(history.current == a)
  }

  @Test func backAndForwardRetraceVisits() {
    var history = BrowserHistory(current: a)
    history.visit(b)
    history.visit(c)
    #expect(history.backEntries.map(\.location) == [a, b])

    #expect(history.goBack()?.location == b)
    #expect(history.current == b)
    #expect(history.canGoForward)
    #expect(history.goBack()?.location == a)
    #expect(!history.canGoBack)

    #expect(history.goForward()?.location == b)
    #expect(history.goForward()?.location == c)
    #expect(history.current == c)
    #expect(!history.canGoForward)
  }

  @Test func visitingAfterGoingBackDiscardsForwardHistory() {
    var history = BrowserHistory(current: a)
    history.visit(b)
    history.visit(c)
    _ = history.goBack()
    let other = URL(filePath: "/other", directoryHint: .isDirectory)
    history.visit(other)

    #expect(!history.canGoForward)
    #expect(history.backEntries.map(\.location) == [a, b])
    #expect(history.current == other)
  }

  @Test func remembersTheSelectionLeftBehindInBothDirections() {
    var history = BrowserHistory(current: a)
    history.visit(b, leaving: [b])
    history.visit(c, leaving: [file])

    let back = history.goBack(leaving: [c])
    #expect(back == BrowserHistory.Entry(location: b, selection: [file]))
    let forward = history.goForward(leaving: [file])
    #expect(forward == BrowserHistory.Entry(location: c, selection: [c]))
    #expect(history.goBack()?.selection == [file])
    #expect(history.goBack()?.selection == [b])
  }

  @Test func visitingTheCurrentFolderChangesNothing() {
    var history = BrowserHistory(current: a)
    history.visit(b)
    let before = history
    history.visit(URL(filePath: "/a/b"))  // same folder, no trailing slash
    history.visit(URL(filePath: "/a/x/../b/", directoryHint: .isDirectory))
    #expect(history == before)
  }

  @Test func keepsOnlyTheNewestEntries() {
    var history = BrowserHistory(current: a)
    for index in 0..<(BrowserHistory.limit + 25) {
      history.visit(URL(filePath: "/folder\(index)", directoryHint: .isDirectory))
    }
    #expect(history.backEntries.count == BrowserHistory.limit)
    #expect(history.backEntries.first?.location.lastPathComponent == "folder24")
    #expect(history.current.lastPathComponent == "folder\(BrowserHistory.limit + 24)")
  }

  @Test func placeKeysIgnoreTrailingSlashesButKeepTheRoot() {
    #expect(BrowserHistory.placeKey(URL(filePath: "/a/b/")) == "/a/b")
    #expect(BrowserHistory.placeKey(URL(filePath: "/a/b")) == "/a/b")
    #expect(BrowserHistory.placeKey(URL(filePath: "/")) == "/")
    #expect(BrowserHistory.placeKey(URL(filePath: "/a/caf\u{E9} folder/")) == "/a/caf\u{E9} folder")
    #expect(BrowserHistory.isSamePlace(URL(filePath: "/a/"), URL(filePath: "/a")))
    #expect(!BrowserHistory.isSamePlace(URL(filePath: "/a"), URL(filePath: "/A2")))
  }

  @Test func placeKeysResolveDotSegmentsInThePathText() {
    #expect(BrowserHistory.placeKey(URL(filePath: "/a/x/../b/")) == "/a/b")
    #expect(BrowserHistory.placeKey(URL(filePath: "/a/./b")) == "/a/b")
    #expect(BrowserHistory.placeKey(URL(filePath: "/a//b")) == "/a/b")
    #expect(BrowserHistory.placeKey(URL(filePath: "/a/.hidden/")) == "/a/.hidden")
    #expect(BrowserHistory.placeKey(URL(filePath: "/Users/..")) == "/")
    #expect(BrowserHistory.placeKey(URL(filePath: "/../..")) == "/")
    #expect(BrowserHistory.isSamePlace(URL(filePath: "/a/x/../b/"), URL(filePath: "/a/./b")))
    #expect(BrowserHistory.isSamePlace(URL(filePath: "/a/./b"), URL(filePath: "/a/b")))
  }

  /// A key is made from the path's text. Asking the disk would be a
  /// file-system call on the main thread, and it shows: the system drops
  /// `/private` from the path of a folder that exists.
  @Test func aPlaceKeyKeepsThePrivatePrefixOfAFolderThatExists() async throws {
    let tree = try FixtureTree.build { FixtureNode.directory("Sub") }
    defer { try? tree.remove() }
    // A listing reports items under the resolved folder, which is in /private.
    let sub = try #require(try await DirectoryReader().items(in: tree.root).first).url
    try #require(sub.path.hasPrefix("/private/"))

    #expect(BrowserHistory.placeKey(sub) == sub.path)
    // The same folder spelled without the prefix is a different place.
    let unresolved = URL(filePath: String(sub.path.dropFirst("/private".count)))
    #expect(!BrowserHistory.isSamePlace(sub, unresolved))
  }
}
