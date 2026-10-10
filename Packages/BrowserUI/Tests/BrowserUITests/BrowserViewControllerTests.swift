import AppKit
import FileSystemCore
import Foundation
import TestSupport
import Testing

@testable import BrowserUI

@Suite @MainActor struct BrowserViewControllerTests {
  @Test func buildsAnIdentifiedLabelledListWithThreeColumns() throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let controller = BrowserViewController(
      location: folder, reader: StubReader(results: [folder: []]))
    let view = controller.view
    #expect(view.identifier?.rawValue == "browser-view")

    let table = try #require(Self.firstSubview(of: NSTableView.self, in: view))
    #expect(table.accessibilityIdentifier() == "file-list")
    #expect(table.accessibilityLabel() == "Files")
    #expect(table.tableColumns.map(\.title) == ["Name", "Size", "Date Modified"])
  }

  @Test func titleIsTheFolderName() {
    #expect(
      BrowserViewController.title(for: URL(filePath: "/Users/someone/Documents")) == "Documents")
    #expect(BrowserViewController.title(for: URL(filePath: "/")) == "/")
  }

  @Test func foldersHaveNoSizeOrDateTextAndFilesShowAByteCount() throws {
    let folder = FileItem(url: URL(filePath: "/fixture/f"), kind: .directory)
    let file = FileItem(
      url: URL(filePath: "/fixture/a"), kind: .file, size: 2_000_000,
      modificationDate: Date(timeIntervalSince1970: 0))
    #expect(BrowserViewController.sizeText(for: folder) == nil)
    #expect(BrowserViewController.modifiedText(for: folder) == nil)
    #expect(
      BrowserViewController.sizeText(for: file)
        == Int64(2_000_000).formatted(.byteCount(style: .file)))
    #expect(try #require(BrowserViewController.modifiedText(for: file)).contains("19"))
  }

  @Test func aMissingValueShowsDashesAndIsSpokenInWords() async throws {
    let location = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let folder = FileItem(url: location.appending(path: "Folder"), kind: .directory)
    let controller = BrowserViewController(
      location: location, reader: StubReader(results: [location: [folder]]))
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value

    let expected = [(column: 1, spoken: "No size"), (column: 2, spoken: "No date")]
    for (column, spoken) in expected {
      let cell = try #require(
        table.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView)
      #expect(cell.textField?.stringValue == "--")
      #expect(cell.accessibilityLabel() == spoken)
      #expect(cell.textField?.accessibilityLabel() == spoken)
    }
    let name = try #require(
      table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
    #expect(name.textField?.stringValue == "Folder")
    #expect(name.accessibilityLabel() != "No name")
  }

  @Test func aRecycledCellStopsSayingItsValueIsMissing() throws {
    let folder = FileItem(url: URL(filePath: "/fixture/Folder"), kind: .directory)
    let file = FileItem(
      url: URL(filePath: "/fixture/a.txt"), kind: .file, size: 2_000_000,
      modificationDate: Date(timeIntervalSince1970: 0))
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: "")
    cell.addSubview(label)
    cell.textField = label

    for (column, spoken) in [
      (BrowserViewController.Column.size, "No size"), (.modified, "No date"),
    ] {
      BrowserViewController.fill(cell, column: column, item: folder)
      #expect(cell.accessibilityLabel() == spoken)
      #expect(label.accessibilityLabel() == spoken)

      BrowserViewController.fill(cell, column: column, item: file)
      #expect(label.stringValue != "--")
      #expect(cell.accessibilityLabel() != spoken)
      #expect(label.accessibilityLabel() != spoken)
    }
  }

  @Test func anItemNamedWithDashesIsNotSpokenAsMissing() {
    let dashes = FileItem(
      url: URL(filePath: "/fixture/--"), kind: .file, size: 1,
      modificationDate: Date(timeIntervalSince1970: 0))
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: "")
    cell.addSubview(label)
    cell.textField = label

    BrowserViewController.fill(cell, column: .name, item: dashes)
    #expect(label.stringValue == "--")
    #expect(cell.accessibilityLabel() != "No name")
    #expect(label.accessibilityLabel() != "No name")
  }

  @Test func enclosingFolderAtTheRootLeavesALoadUnderWayToFinish() async throws {
    let root = URL(filePath: "/", directoryHint: .isDirectory)
    let gate = Gate()
    let reader = StubReader(
      results: [root: [FileItem(url: root.appending(path: "Users"), kind: .directory)]],
      gates: [root: gate])
    let controller = BrowserViewController(location: root, reader: reader)
    _ = controller.view
    await gate.waitUntilReached()

    controller.goToEnclosingFolder(nil)
    await gate.open()
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.items.map(\.name) == ["Users"])
  }

  @Test func backAndForwardWithoutHistoryLeaveALoadUnderWayToFinish() async throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let actions: [@MainActor (BrowserViewController) -> Void] = [
      { $0.goBack(nil) }, { $0.goForward(nil) },
    ]
    for action in actions {
      let gate = Gate()
      let reader = StubReader(
        results: [folder: [FileItem(url: folder.appending(path: "a.txt"), kind: .file)]],
        gates: [folder: gate])
      let controller = BrowserViewController(location: folder, reader: reader)
      _ = controller.view
      await gate.waitUntilReached()

      action(controller)
      await gate.open()
      await controller.loadTask?.value
      #expect(controller.model.state == .loaded)
      #expect(controller.model.items.map(\.name) == ["a.txt"])
    }
  }

  @Test func backWithHistoryCancelsALoadUnderWay() async throws {
    let parent = URL(filePath: "/fixture/parent", directoryHint: .isDirectory)
    let child = parent.appending(path: "child", directoryHint: .isDirectory)
    let gate = Gate()
    let reader = StubReader(
      results: [
        parent: [FileItem(url: child, kind: .directory)],
        child: [FileItem(url: child.appending(path: "inner.txt"), kind: .file)],
      ],
      gates: [parent: gate])
    let controller = BrowserViewController(location: child, reader: reader)
    _ = controller.view
    await controller.loadTask?.value

    // The move to the parent is held at the gate, with the child in the history.
    controller.goToEnclosingFolder(nil)
    await gate.waitUntilReached()
    #expect(controller.model.canGoBack)
    let held = try #require(controller.loadTask)

    controller.goBack(nil)
    // Required, not expected: a load that was not replaced would be awaited at the gate forever.
    try #require(held.isCancelled)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location == child)
    #expect(controller.model.items.map(\.name) == ["inner.txt"])

    // The parent's listing arrives late and changes nothing.
    await gate.open()
    await held.value
    #expect(controller.model.location == child)
    #expect(controller.model.items.map(\.name) == ["inner.txt"])
  }

  /// A browser that has gone from `/fixture` into its folder `child`, with
  /// both listings finished, so there is one place to go back to.
  private func browserOneFolderIn() async -> (
    controller: BrowserViewController, parent: URL, child: URL
  ) {
    let parent = URL(filePath: "/fixture", directoryHint: .isDirectory)
    let child = parent.appending(path: "child", directoryHint: .isDirectory)
    let reader = StubReader(results: [
      parent: [FileItem(url: child, kind: .directory)],
      child: [
        FileItem(url: child.appending(path: "inner", directoryHint: .isDirectory), kind: .directory)
      ],
    ])
    let controller = BrowserViewController(location: parent, reader: reader)
    _ = controller.view
    await controller.loadTask?.value
    await controller.model.navigate(to: child)
    return (controller, parent, child)
  }

  @Test func backSentTwiceBeforeTheFirstStartsStillShowsThePreviousFolder() async throws {
    let (controller, parent, _) = await browserOneFolderIn()
    try #require(controller.model.canGoBack)

    // No await between the two: the first one's task has not started.
    controller.goBack(nil)
    controller.goBack(nil)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location == parent)
    #expect(controller.model.items.map(\.name) == ["child"])
    #expect(controller.model.canGoForward)
  }

  @Test func forwardSentTwiceBeforeTheFirstStartsStillShowsTheNextFolder() async throws {
    let (controller, _, child) = await browserOneFolderIn()
    await controller.model.goBack()
    try #require(controller.model.canGoForward)

    controller.goForward(nil)
    controller.goForward(nil)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location == child)
    #expect(controller.model.items.map(\.name) == ["inner"])
  }

  @Test func enclosingFolderSentTwiceOneLevelBelowTheRootStillShowsTheRoot() async throws {
    let root = URL(filePath: "/", directoryHint: .isDirectory)
    let fixture = URL(filePath: "/fixture", directoryHint: .isDirectory)
    let reader = StubReader(results: [
      root: [FileItem(url: fixture, kind: .directory)], fixture: [],
    ])
    let controller = BrowserViewController(location: fixture, reader: reader)
    _ = controller.view
    await controller.loadTask?.value

    controller.goToEnclosingFolder(nil)
    controller.goToEnclosingFolder(nil)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location.path == "/")
    #expect(controller.model.items.map(\.name) == ["fixture"])
    #expect(controller.model.selection.map(\.lastPathComponent) == ["fixture"])
  }

  @Test func backSentBeforeAnOpenStartsReturnsFromTheFolderThatWasOpened() async throws {
    let (controller, _, child) = await browserOneFolderIn()
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    table.selectRowIndexes([0], byExtendingSelection: false)
    try #require(controller.model.selection.map(\.lastPathComponent) == ["inner"])

    // Open "inner", then Back, with no await between.
    controller.openSelection(nil)
    controller.goBack(nil)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location == child)
    #expect(controller.model.items.map(\.name) == ["inner"])
    #expect(controller.model.history.forwardEntries.map(\.location.lastPathComponent) == ["inner"])
  }

  @Test func enablesEnclosingFolderEverywhereButTheRoot() {
    let enclosingFolder = NSMenuItem(
      title: "Enclosing Folder", action: #selector(BrowserViewController.goToEnclosingFolder(_:)),
      keyEquivalent: "")
    let root = BrowserViewController(
      location: URL(filePath: "/", directoryHint: .isDirectory), reader: StubReader(results: [:]))
    #expect(!root.validateUserInterfaceItem(enclosingFolder))

    let subfolder = BrowserViewController(
      location: URL(filePath: "/fixture/folder", directoryHint: .isDirectory),
      reader: StubReader(results: [:]))
    #expect(subfolder.validateUserInterfaceItem(enclosingFolder))
  }

  @Test func showsOneRowPerVisibleItemAfterLoading() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("a.txt")
      FixtureNode.file("b.txt")
      FixtureNode.hiddenFile("hidden")
      FixtureNode.directory("Sub")
    }
    defer { try? tree.remove() }

    let controller = BrowserViewController(location: tree.root)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value

    #expect(table.numberOfRows == 3)
    #expect(controller.title == tree.root.lastPathComponent)
    let cell = try #require(
      table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
    #expect(cell.textField?.stringValue == "a.txt")
  }

  @Test func enablesBackAndForwardOnlyWhenThereIsHistory() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Sub")
      FixtureNode.file("a.txt")
    }
    defer { try? tree.remove() }
    let controller = BrowserViewController(location: tree.root)
    // A window with the real toolbar, so the buttons themselves are read.
    let window = NSWindow(contentViewController: controller)
    let source = BrowserToolbar()
    window.toolbar = source.makeToolbar()
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    // The list has focus, as it does once the window is on screen.
    try #require(window.makeFirstResponder(table))
    let buttons = try #require(window.toolbar).items.compactMap { $0.view as? NSButton }
    try #require(buttons.count == 2)
    let (backButton, forwardButton) = (buttons[0], buttons[1])
    #expect(buttons.map { $0.accessibilityIdentifier() } == ["go-back", "go-forward"])
    await controller.loadTask?.value

    let back = NSMenuItem(
      title: "Back", action: #selector(BrowserViewController.goBack(_:)), keyEquivalent: "")
    let forward = NSMenuItem(
      title: "Forward", action: #selector(BrowserViewController.goForward(_:)), keyEquivalent: "")
    /// What the menu items and the toolbar buttons each say, which must agree.
    func enabled() -> [Bool] {
      [
        controller.validateUserInterfaceItem(back), backButton.isEnabled,
        controller.validateUserInterfaceItem(forward), forwardButton.isEnabled,
      ]
    }
    #expect(enabled() == [false, false, false, false])

    await controller.model.navigate(to: tree.url("Sub"))
    #expect(enabled() == [true, true, false, false])

    // The button's own action, sent the way a click sends it: up the
    // responder chain from the window's first responder.
    let backAction = try #require(backButton.action)
    #expect(window.firstResponder?.tryToPerform(backAction, with: backButton) == true)
    await controller.loadTask?.value
    #expect(controller.model.location.lastPathComponent == tree.root.lastPathComponent)
    #expect(enabled() == [false, false, true, true])

    let forwardAction = try #require(forwardButton.action)
    #expect(window.firstResponder?.tryToPerform(forwardAction, with: forwardButton) == true)
    await controller.loadTask?.value
    #expect(controller.model.location.lastPathComponent == "Sub")
    #expect(enabled() == [true, true, false, false])
  }

  @Test func selectionFlowsBetweenTheTableAndTheModel() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("a.txt")
      FixtureNode.file("b.txt")
      FixtureNode.directory("Sub")
    }
    defer { try? tree.remove() }
    let controller = BrowserViewController(location: tree.root)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value

    // The user selects rows: the model learns which items.
    table.selectRowIndexes([0, 2], byExtendingSelection: false)
    #expect(controller.model.selection.map(\.lastPathComponent).sorted() == ["Sub", "a.txt"])

    // Open is offered for one folder, not for a file or several items.
    let open = NSMenuItem(
      title: "Open", action: #selector(BrowserViewController.openSelection(_:)), keyEquivalent: "")
    #expect(!controller.validateUserInterfaceItem(open))
    table.selectRowIndexes([0], byExtendingSelection: false)
    #expect(!controller.validateUserInterfaceItem(open))
    table.selectRowIndexes([2], byExtendingSelection: false)
    #expect(controller.validateUserInterfaceItem(open))

    // Navigation restores a selection: the table shows it.
    await controller.model.navigate(to: tree.url("Sub"))
    #expect(table.selectedRowIndexes.isEmpty)
    await controller.model.goBack()
    #expect(table.selectedRowIndexes == [2])
  }

  /// A browser on a folder of a.txt, b.txt, c.txt and d.txt, loaded, with d.txt
  /// selected in the table as a user would select it.
  private func browserWithTheLastOfFourFilesSelected() async throws -> (
    tree: FixtureTree, controller: BrowserViewController, table: NSTableView
  ) {
    let tree = try FixtureTree.build {
      for name in ["a.txt", "b.txt", "c.txt", "d.txt"] { FixtureNode.file(name) }
    }
    let controller = BrowserViewController(location: tree.root)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value
    table.selectRowIndexes([3], byExtendingSelection: false)
    #expect(controller.model.selection.map(\.lastPathComponent) == ["d.txt"])
    return (tree, controller, table)
  }

  @Test func reloadingKeepsTheSelectedRowWhenAnEarlierItemIsRemoved() async throws {
    let (tree, controller, table) = try await browserWithTheLastOfFourFilesSelected()
    defer { try? tree.remove() }

    try FileManager.default.removeItem(at: tree.url("a.txt"))
    await controller.model.load()
    #expect(table.numberOfRows == 3)
    #expect(table.selectedRowIndexes == [2])
    #expect(controller.model.selection.map(\.lastPathComponent) == ["d.txt"])
  }

  @Test func reloadingSelectsNothingWhenTheSelectedItemIsGone() async throws {
    let (tree, controller, table) = try await browserWithTheLastOfFourFilesSelected()
    defer { try? tree.remove() }

    try FileManager.default.removeItem(at: tree.url("d.txt"))
    await controller.model.load()
    #expect(table.numberOfRows == 3)
    #expect(table.selectedRowIndexes.isEmpty)
    #expect(controller.model.selection.isEmpty)
  }

  private static func firstSubview<View: NSView>(of type: View.Type, in view: NSView) -> View? {
    if let match = view as? View { return match }
    for subview in view.subviews {
      if let match = firstSubview(of: type, in: subview) { return match }
    }
    if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
      return firstSubview(of: type, in: document)
    }
    return nil
  }
}
