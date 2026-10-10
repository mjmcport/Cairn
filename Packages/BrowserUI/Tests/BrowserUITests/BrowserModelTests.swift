import FileSystemCore
import Foundation
import TestSupport
import Testing

@testable import BrowserUI

@Suite @MainActor struct BrowserModelTests {
  private func makeTree() throws -> FixtureTree {
    try FixtureTree.build {
      FixtureNode.file("b.txt")
      FixtureNode.file("a.txt", size: 10)
      FixtureNode.hiddenFile("secret")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
      }
      FixtureNode.bundle("Sample")
    }
  }

  @Test func loadsSortedVisibleItems() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    #expect(model.state == .loading)

    await model.load()
    #expect(model.state == .loaded)
    #expect(model.items.map(\.name) == ["a.txt", "b.txt", "Sample.app", "Sub"])
  }

  @Test func showsHiddenFilesWhenAsked() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    model.showsHiddenFiles = true

    await model.load()
    #expect(model.items.map(\.name).contains(".secret"))
    #expect(model.items.count == 5)
  }

  @Test func appliesTheChosenSort() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    model.sort = FileItemSort(ascending: false, foldersFirst: true)

    await model.load()
    #expect(model.items.map(\.name) == ["Sub", "Sample.app", "b.txt", "a.txt"])
  }

  @Test func openingAFolderNavigatesAndOpeningAFileOrPackageDoesNot() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()

    let file = try #require(model.items.first { $0.name == "a.txt" })
    let package = try #require(model.items.first { $0.name == "Sample.app" })
    #expect(await model.open(file) == false)
    #expect(await model.open(package) == false)
    #expect(model.location == tree.root)

    let folder = try #require(model.items.first { $0.name == "Sub" })
    #expect(await model.open(folder) == true)
    #expect(model.location.lastPathComponent == "Sub")
    #expect(model.items.map(\.name) == ["inner.txt"])
  }

  @Test func navigatesToTheEnclosingFolderAndStopsAtTheRoot() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.url("Sub"))
    #expect(model.enclosingFolder?.path == tree.root.path)

    await model.navigateToEnclosingFolder()
    #expect(model.location.path == tree.root.path)
    #expect(model.items.count == 4)

    let root = BrowserModel(location: URL(filePath: "/"), reader: StubReader(results: [:]))
    #expect(root.enclosingFolder == nil)
    await root.navigateToEnclosingFolder()
    #expect(root.location.path == "/")

    // A location that only standardizes to the root is the root too.
    let dotted = BrowserModel(
      location: URL(filePath: "/Users/.."), reader: StubReader(results: [:]))
    #expect(dotted.enclosingFolder == nil)
  }

  @Test func theEnclosingFolderComesFromThePathText() async throws {
    func enclosingFolder(of path: String) -> String? {
      BrowserModel(location: URL(filePath: path), reader: StubReader(results: [:]))
        .enclosingFolder?.path
    }
    #expect(enclosingFolder(of: "/") == nil)
    #expect(enclosingFolder(of: "/Users/..") == nil)
    #expect(enclosingFolder(of: "/a") == "/")
    #expect(enclosingFolder(of: "/a/b/") == "/a")
    #expect(enclosingFolder(of: "/a/b/../c") == "/a")
    #expect(enclosingFolder(of: "/a/caf\u{E9} folder/b") == "/a/caf\u{E9} folder")

    // A folder that exists under /private keeps the prefix: nothing asked the disk.
    let tree = try makeTree()
    defer { try? tree.remove() }
    let listed = try await DirectoryReader().items(in: tree.root)
    let sub = try #require(listed.first { $0.name == "Sub" }).url
    try #require(sub.path.hasPrefix("/private/"))
    let model = BrowserModel(location: sub, reader: StubReader(results: [:]))
    #expect(model.enclosingFolder?.path == sub.deletingLastPathComponent().path)
    #expect(model.enclosingFolder?.path.hasPrefix("/private/") == true)
  }

  @Test func enclosingFolderSelectsTheFolderJustLeftBehindASymbolicLink() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Real") {
        FixtureNode.directory("Inner") {
          FixtureNode.file("deep.txt")
        }
        FixtureNode.file("beside.txt")
      }
      FixtureNode.symlink("Link", to: "Real")
    }
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.url("Link"))
    await model.load()
    #expect(model.items.map(\.name) == ["beside.txt", "Inner"])

    let inner = try #require(model.items.first { $0.name == "Inner" })
    #expect(await model.open(inner) == true)
    #expect(model.items.map(\.name) == ["deep.txt"])

    await model.navigateToEnclosingFolder()
    #expect(model.items.map(\.name) == ["beside.txt", "Inner"])
    #expect(model.selection == [inner.url])
  }

  @Test func aFailedListingClearsTheItemsAndReportsWhy() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()
    #expect(!model.items.isEmpty)

    await model.navigate(to: tree.url("missing"))
    #expect(model.items.isEmpty)
    guard case .failed(let message) = model.state else {
      Issue.record("Expected a failed state, got \(model.state)")
      return
    }
    #expect(!message.isEmpty)
  }

  @Test func notifiesWhenLoadingStartsAndFinishes() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    var states: [BrowserModel.State] = []
    model.onChange = { states.append(model.state) }

    await model.load()
    #expect(states == [.loading, .loaded])
  }

  @Test func aSlowListingOfAFolderTheUserLeftDoesNotOverwriteTheCurrentOne() async throws {
    let slow = URL(filePath: "/fixture/slow", directoryHint: .isDirectory)
    let fast = URL(filePath: "/fixture/fast", directoryHint: .isDirectory)
    let gate = Gate()
    let reader = StubReader(
      results: [
        slow: [FileItem(url: slow.appending(path: "stale.txt"), kind: .file)],
        fast: [FileItem(url: fast.appending(path: "current.txt"), kind: .file)],
      ],
      gates: [slow: gate]
    )
    let model = BrowserModel(location: slow, reader: reader)

    let slowLoad = Task { await model.load() }
    await gate.waitUntilReached()
    await model.navigate(to: fast)
    #expect(model.items.map(\.name) == ["current.txt"])

    await gate.open()
    await slowLoad.value
    #expect(model.location == fast)
    #expect(model.items.map(\.name) == ["current.txt"])
    #expect(model.state == .loaded)
  }

  @Test func aCancelledLoadLeavesTheModelUntouched() async throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let gate = Gate()
    let reader = StubReader(results: [folder: []], gates: [folder: gate])
    let model = BrowserModel(location: folder, reader: reader)

    let load = Task { await model.load() }
    await gate.waitUntilReached()
    load.cancel()
    await gate.open()
    await load.value
    #expect(model.state == .loading)
  }

  // MARK: History and selection

  private func selectedNames(_ model: BrowserModel) -> [String] {
    model.selection.map(\.lastPathComponent).sorted()
  }

  @Test func backAndForwardRetraceNavigation() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()
    #expect(!model.canGoBack)
    #expect(!model.canGoForward)

    await model.navigate(to: tree.url("Sub"))
    #expect(model.canGoBack)
    #expect(model.items.map(\.name) == ["inner.txt"])

    await model.goBack()
    #expect(model.location.path == tree.root.path)
    #expect(model.items.count == 4)
    #expect(model.canGoForward)
    #expect(!model.canGoBack)

    await model.goForward()
    #expect(model.location.lastPathComponent == "Sub")
    #expect(model.items.map(\.name) == ["inner.txt"])
    #expect(!model.canGoForward)
  }

  @Test func goingBackRestoresWhatWasSelected() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()
    model.selection = [tree.url("a.txt"), tree.url("Sub")]

    await model.navigate(to: tree.url("Sub"))
    #expect(model.selection.isEmpty)
    model.selection = [tree.url("Sub/inner.txt")]

    await model.goBack()
    #expect(selectedNames(model) == ["Sub", "a.txt"])
    await model.goForward()
    #expect(selectedNames(model) == ["inner.txt"])
  }

  @Test func goingToTheEnclosingFolderSelectsTheFolderJustLeft() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.url("Sub"))
    await model.load()

    await model.navigateToEnclosingFolder()
    #expect(selectedNames(model) == ["Sub"])
    #expect(model.canGoBack)
    // The selection uses the listed item's own URL, so the view can match it.
    #expect(model.selection.isSubset(of: Set(model.items.map(\.url))))

    await model.goBack()
    #expect(model.location.lastPathComponent == "Sub")
  }

  @Test func aRememberedSelectionSurvivesLeavingBeforeTheListingArrives() async throws {
    let a = URL(filePath: "/fixture/a", directoryHint: .isDirectory)
    let b = URL(filePath: "/fixture/b", directoryHint: .isDirectory)
    let x = a.appending(path: "x.txt")
    let gate = Gate()
    let reader = StubReader(
      results: [
        a: [FileItem(url: x, kind: .file), FileItem(url: a.appending(path: "y.txt"), kind: .file)],
        b: [],
      ],
      gates: [a: gate])
    let model = BrowserModel(location: a, reader: reader)
    // A is left without being listed, so its gate first holds the return to it.
    model.selection = [x]
    await model.navigate(to: b)

    let firstReturn = Task { await model.goBack() }
    await gate.waitUntilReached()
    // A's listing has not arrived: x is still waiting to be restored.
    await model.goForward()
    #expect(model.location == b)

    let secondReturn = Task { await model.goBack() }
    await gate.open()
    await firstReturn.value
    await secondReturn.value
    #expect(model.location == a)
    #expect(model.state == .loaded)
    #expect(model.selection == [x])
  }

  @Test func theFolderJustLeftStaysSelectedAfterLeavingTheEnclosingFolderEarly() async throws {
    let parent = URL(filePath: "/fixture/parent", directoryHint: .isDirectory)
    let child = parent.appending(path: "child", directoryHint: .isDirectory)
    let gate = Gate()
    let reader = StubReader(
      results: [
        parent: [
          FileItem(url: child, kind: .directory),
          FileItem(url: parent.appending(path: "other.txt"), kind: .file),
        ],
        child: [],
      ],
      gates: [parent: gate])
    let model = BrowserModel(location: child, reader: reader)
    await model.load()

    let up = Task { await model.navigateToEnclosingFolder() }
    await gate.waitUntilReached()
    // The parent's listing has not arrived: the child is still waiting to be selected.
    await model.goBack()
    #expect(model.location == child)

    let forward = Task { await model.goForward() }
    await gate.open()
    await up.value
    await forward.value
    #expect(model.location.path == parent.path)
    #expect(model.state == .loaded)
    #expect(model.selection == [child])
  }

  @Test func goingToTheEnclosingFolderAtTheRootAddsNoHistoryAndReportsNoChange() async throws {
    let model = BrowserModel(location: URL(filePath: "/"), reader: StubReader(results: [:]))
    var changes = 0
    model.onChange = { changes += 1 }

    await model.navigateToEnclosingFolder()
    #expect(!model.canGoBack)
    #expect(!model.canGoForward)
    #expect(changes == 0)
    #expect(model.location.path == "/")
  }

  @Test func aSelectionIsMatchedByNameHoweverItsFolderIsSpelled() {
    // A listing reports items under the folder a symbolic link leads to.
    let listed = URL(filePath: "/private/tmp/x", directoryHint: .isDirectory)
    let items = [
      FileItem(url: listed.appending(path: "Sub", directoryHint: .isDirectory), kind: .directory),
      FileItem(url: listed.appending(path: "a.txt"), kind: .file),
    ]
    let wanted: Set<URL> = [URL(filePath: "/tmp/x/Sub"), URL(filePath: "/tmp/x/gone.txt")]
    #expect(BrowserModel.matching(wanted, in: items) == [items[0].url])
    #expect(BrowserModel.matching([], in: items).isEmpty)
  }

  @Test func reloadingKeepsTheSelectionOfItemsThatStillExist() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()
    model.selection = [tree.url("a.txt"), tree.url("b.txt")]

    try FileManager.default.removeItem(at: tree.url("b.txt"))
    await model.load()
    #expect(selectedNames(model) == ["a.txt"])
  }

  @Test func navigatingToTheCurrentFolderReloadsWithoutAddingHistory() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()

    await model.navigate(to: URL(filePath: tree.root.path))
    #expect(!model.canGoBack)
    #expect(model.items.count == 4)
  }

  @Test func aFailedFolderIsStillInHistorySoBackLeavesIt() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()

    await model.navigate(to: tree.url("missing"))
    #expect(model.canGoBack)
    await model.goBack()
    #expect(model.state == .loaded)
    #expect(model.items.count == 4)
  }

  @Test func backAndForwardDoNothingWithoutHistory() async throws {
    let tree = try makeTree()
    defer { try? tree.remove() }
    let model = BrowserModel(location: tree.root)
    await model.load()
    var changes = 0
    model.onChange = { changes += 1 }

    await model.goBack()
    await model.goForward()
    #expect(changes == 0)
    #expect(model.location.path == tree.root.path)
  }
}
