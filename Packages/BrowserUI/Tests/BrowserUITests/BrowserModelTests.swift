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
}
