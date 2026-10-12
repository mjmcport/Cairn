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

  // MARK: A browser in a tab

  /// A browser on `/fixture`, loaded, with its only row, the folder `child`,
  /// selected. `gate` holds the listing of `child`.
  private func browserAboutToOpenAFolder(holdingItAt gate: Gate? = nil) async throws -> (
    controller: BrowserViewController, table: NSTableView
  ) {
    let parent = URL(filePath: "/fixture", directoryHint: .isDirectory)
    let child = parent.appending(path: "child", directoryHint: .isDirectory)
    let reader = StubReader(
      results: [parent: [FileItem(url: child, kind: .directory)], child: []],
      gates: gate.map { [child: $0] } ?? [:])
    let controller = BrowserViewController(location: parent, reader: reader)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value
    table.selectRowIndexes([0], byExtendingSelection: false)
    return (controller, table)
  }

  @Test func openingAFolderReportsTheNewTitleAsTheCommandIsHandled() async throws {
    let gate = Gate()
    let (controller, _) = try await browserAboutToOpenAFolder(holdingItAt: gate)
    #expect(controller.title == "fixture")
    var reported: [String?] = []
    controller.onTitleChange = { reported.append(controller.title) }

    // Read straight after the command: the listing has not even started.
    controller.openSelection(nil)
    #expect(reported == ["child"])

    await gate.open()
    await controller.loadTask?.value
    #expect(reported == ["child"])
  }

  @Test func aBrowserHasItsTitleBeforeItsViewIsLoaded() {
    let controller = BrowserViewController(
      location: URL(filePath: "/fixture/folder", directoryHint: .isDirectory),
      reader: StubReader(results: [:]))
    #expect(controller.title == "folder")
    #expect(!controller.isViewLoaded)
  }

  @Test func backWithNoHistoryReportsNoTitleChange() async throws {
    let (controller, _) = try await browserAboutToOpenAFolder()
    var reports = 0
    controller.onTitleChange = { reports += 1 }
    controller.goBack(nil)
    await controller.loadTask?.value
    #expect(reports == 0)
  }

  /// A window whose content holds the browser's view beside another view.
  private func window(holding controller: BrowserViewController) -> (
    window: NSWindow, other: FocusableView
  ) {
    let content = NSViewController()
    content.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let other = FocusableView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    content.view.addSubview(other)
    content.addChild(controller)
    content.view.addSubview(controller.view)
    let window = NSWindow(contentViewController: content)
    return (window, other)
  }

  @Test func aBrowserLeavesTheWindowsTitleAndKeyboardFocusAlone() async throws {
    let (controller, _) = try await browserAboutToOpenAFolder()
    let (window, other) = window(holding: controller)
    window.title = "Someone else's title"
    try #require(window.makeFirstResponder(other))

    // What AppKit sends once the browser's view is on screen.
    controller.viewDidAppear()
    controller.openSelection(nil)
    await controller.loadTask?.value
    try #require(controller.model.state == .loaded && controller.title == "child")
    #expect(window.title == "Someone else's title")
    #expect(window.firstResponder === other)
  }

  @Test func askedToTakeFocusTheFileListBecomesFirstResponder() async throws {
    let (controller, table) = try await browserAboutToOpenAFolder()
    let (window, other) = window(holding: controller)
    try #require(window.makeFirstResponder(other))

    controller.focusList()
    #expect(window.firstResponder === table)
  }

  @Test func cancellingTheLoadStopsAListingUnderWay() async throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let gate = Gate()
    let reader = StubReader(
      results: [folder: [FileItem(url: folder.appending(path: "a.txt"), kind: .file)]],
      gates: [folder: gate])
    let controller = BrowserViewController(location: folder, reader: reader)
    _ = controller.view
    await gate.waitUntilReached()
    let held = try #require(controller.loadTask)

    controller.cancelLoad()
    // Required, not expected: a listing still running would publish below.
    try #require(held.isCancelled)

    // The listing arrives late and changes nothing.
    await gate.open()
    await held.value
    #expect(controller.model.state == .loading)
    #expect(controller.model.items.isEmpty)
  }

  // MARK: First rows, then the sorted list

  private let big = URL(filePath: "/fixture/big", directoryHint: .isDirectory)
  private let small = URL(filePath: "/fixture/small", directoryHint: .isDirectory)

  private func file(_ name: String, in folder: URL) -> FileItem {
    FileItem(url: folder.appending(path: name), kind: .file)
  }

  /// A listing of `big` that hands over `first` and is then held at `gate`
  /// before it hands over `all`. `small` holds one file and is not held.
  private func reader(first: [FileItem], all: [FileItem], heldAt gate: Gate) -> StubReader {
    StubReader(
      results: [big: all, small: [file("only.txt", in: small)]],
      firstItems: [big: first],
      gatesAfterFirstItems: [big: gate])
  }

  /// The same, for a folder of plain files.
  private func reader(first: [String], all: [String], heldAt gate: Gate) -> StubReader {
    reader(
      first: first.map { file($0, in: big) }, all: all.map { file($0, in: big) }, heldAt: gate)
  }

  /// `count` names that sort in the order given, however they are listed.
  private func numberedNames(_ count: Int) -> [String] {
    (0..<count).map { FixtureNames.numbered($0) }
  }

  /// The names the table shows, read from its cells.
  private func rowNames(of table: NSTableView) -> [String?] {
    (0..<table.numberOfRows).map {
      (table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?
        .textField?.stringValue
    }
  }

  /// A browser on `big` whose load is held between its two events, with the
  /// first rows in the table.
  private func browserShowingFirstRows(of reader: StubReader, heldAt gate: Gate) async throws -> (
    controller: BrowserViewController, table: NSTableView
  ) {
    let controller = BrowserViewController(location: big, reader: reader)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await gate.waitUntilReached()
    return (controller, table)
  }

  /// A browser that showed `big`, settled, has gone on to `small` and is on
  /// its way back, held between the two events of `big`. `selecting` is the
  /// row that was selected in `big` when it was left.
  private func browserGoingBackToBig(
    reader: StubReader, heldAt gate: Gate, selecting row: Int? = nil
  ) async throws -> (controller: BrowserViewController, table: NSTableView) {
    await gate.open()
    let controller = BrowserViewController(location: big, reader: reader)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value
    if let row {
      table.selectRowIndexes([row], byExtendingSelection: false)
    }
    await controller.model.navigate(to: small)

    await gate.close()
    controller.goBack(nil)
    await gate.waitUntilReached()
    return (controller, table)
  }

  @Test func theTableShowsTheFirstRowsUnsortedAndThenTheSortedList() async throws {
    let gate = Gate()
    let (controller, table) = try await browserShowingFirstRows(
      of: reader(first: ["c", "a"], all: ["c", "a", "b"], heldAt: gate), heldAt: gate)
    let status = try #require(
      controller.view.subviews.first { $0.accessibilityIdentifier() == "browser-status" })

    #expect(rowNames(of: table) == ["c", "a"])
    #expect(table.selectedRowIndexes.isEmpty)
    #expect(status.isHidden)

    await gate.open()
    await controller.loadTask?.value
    #expect(rowNames(of: table) == ["a", "b", "c"])
    #expect(status.isHidden)
  }

  @Test func aRememberedRowBeyondTheFirstRowsIsSelectedOnceWhenTheListSettles() async throws {
    let gate = Gate()
    // z was selected when the folder was left, and is not among the first rows.
    let (controller, table) = try await browserGoingBackToBig(
      reader: reader(first: ["c", "a"], all: ["c", "a", "b", "z"], heldAt: gate), heldAt: gate,
      selecting: 3)
    #expect(rowNames(of: table) == ["c", "a"])
    #expect(table.selectedRowIndexes.isEmpty)

    var selectionChanges = 0
    let observer = NotificationCenter.default.addObserver(
      forName: NSTableView.selectionDidChangeNotification, object: table, queue: nil
    ) { _ in
      MainActor.assumeIsolated { selectionChanges += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    await gate.open()
    await controller.loadTask?.value
    #expect(rowNames(of: table) == ["a", "b", "c", "z"])
    #expect(table.selectedRowIndexes == [3])
    #expect(selectionChanges == 1)
    #expect(controller.model.selection.map(\.lastPathComponent) == ["z"])
  }

  @Test func aRowSelectedInTheFirstRowsStaysSelectedAndIsBroughtIntoView() async throws {
    let names = numberedNames(200)
    let gate = Gate()
    // The first rows are the folder's last 50 items, so the first of them moves
    // from row 0 to row 150 when the list settles.
    let (controller, table) = try await browserShowingFirstRows(
      of: reader(first: Array(names[150...]), all: names.reversed(), heldAt: gate), heldAt: gate)
    let window = NSWindow(contentViewController: controller)
    window.layoutIfNeeded()
    try #require(rowNames(of: table).first == names[150])

    table.selectRowIndexes([0], byExtendingSelection: false)
    try #require(!table.rows(in: table.visibleRect).contains(150))

    await gate.open()
    await controller.loadTask?.value
    #expect(table.numberOfRows == 200)
    #expect(table.selectedRowIndexes == [150])
    #expect(controller.model.selection.map(\.lastPathComponent) == [names[150]])
    #expect(table.rows(in: table.visibleRect).contains(150))
  }

  @Test func theListKeepsItsScrollOffsetWhenItSettlesWithNothingSelected() async throws {
    let names = numberedNames(400)
    let gate = Gate()
    let (controller, table) = try await browserShowingFirstRows(
      of: reader(first: Array(names[..<200].reversed()), all: names, heldAt: gate), heldAt: gate)
    let window = NSWindow(contentViewController: controller)
    window.layoutIfNeeded()
    let clipView = try #require(table.enclosingScrollView?.contentView)

    table.scrollRowToVisible(120)
    let scrolled = clipView.bounds.origin
    try #require(scrolled.y > 0)

    await gate.open()
    await controller.loadTask?.value
    #expect(table.numberOfRows == 400)
    #expect(clipView.bounds.origin == scrolled)
  }

  @Test func keyboardFocusStaysWhereItIsThroughBothArrivals() async throws {
    for focusInTheList in [false, true] {
      let gate = Gate()
      let controller = BrowserViewController(
        location: big, reader: reader(first: ["c", "a"], all: ["c", "a", "b"], heldAt: gate))
      let (window, other) = window(holding: controller)
      let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
      let focused: NSResponder = focusInTheList ? table : other
      try #require(window.makeFirstResponder(focused))

      await gate.waitUntilReached()
      try #require(table.numberOfRows == 2)
      #expect(window.firstResponder === focused)

      await gate.open()
      await controller.loadTask?.value
      try #require(table.numberOfRows == 3)
      #expect(window.firstResponder === focused)
    }
  }

  @Test func openingAFolderInTheFirstRowsCancelsTheHeldLoadAndShowsThatFolder() async throws {
    let sub = big.appending(path: "Sub", directoryHint: .isDirectory)
    let folder = FileItem(url: sub, kind: .directory)
    let gate = Gate()
    var reader = reader(
      first: [file("c", in: big), folder], all: [file("c", in: big), folder, file("a", in: big)],
      heldAt: gate)
    reader.results[sub] = [file("inner.txt", in: sub)]
    let (controller, table) = try await browserShowingFirstRows(of: reader, heldAt: gate)
    let held = try #require(controller.loadTask)

    table.selectRowIndexes([1], byExtendingSelection: false)
    controller.openSelection(nil)
    // Required, not expected: a load that was not replaced would be awaited at the gate forever.
    try #require(held.isCancelled)
    await controller.loadTask?.value
    #expect(controller.model.location == sub)
    #expect(controller.model.state == .loaded)
    #expect(rowNames(of: table) == ["inner.txt"])

    // The rest of the folder that was left arrives late and changes nothing.
    await gate.open()
    await held.value
    #expect(controller.model.location == sub)
    #expect(rowNames(of: table) == ["inner.txt"])
  }

  @Test func backSentTwiceWhileTheFirstRowsAreShowingEndsOnThePreviousFolder() async throws {
    let gate = Gate()
    let controller = BrowserViewController(
      location: small, reader: reader(first: ["c", "a"], all: ["c", "a", "b"], heldAt: gate))
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    await controller.loadTask?.value
    controller.model.move(to: big)
    let held = Task { await controller.model.load() }
    await gate.waitUntilReached()
    try #require(rowNames(of: table) == ["c", "a"])

    // No await between the two: the first one's task has not started.
    controller.goBack(nil)
    controller.goBack(nil)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location == small)
    #expect(rowNames(of: table) == ["only.txt"])

    await gate.open()
    await held.value
    #expect(controller.model.location == small)
    #expect(rowNames(of: table) == ["only.txt"])
  }

  @Test func cancellingTheLoadWhileTheFirstRowsAreShowingPublishesNothingMore() async throws {
    let gate = Gate()
    let (controller, table) = try await browserShowingFirstRows(
      of: reader(first: ["c", "a"], all: ["c", "a", "b"], heldAt: gate), heldAt: gate)
    let held = try #require(controller.loadTask)

    controller.cancelLoad()
    try #require(held.isCancelled)
    await gate.open()
    await held.value
    #expect(controller.model.state == .loading)
    #expect(rowNames(of: table) == ["c", "a"])
  }

  @Test func aFolderOfOneBatchReachesTheTableAsOftenAsBefore() async throws {
    /// How many times the model told the controller to redraw while it
    /// opened `folder`, which is how often the table is reloaded.
    func redraws(opening folder: URL, reader: StubReader) async -> Int {
      let controller = BrowserViewController(location: folder, reader: reader)
      _ = controller.view
      var redraws = 0
      let redraw = controller.model.onChange
      controller.model.onChange = {
        redraws += 1
        redraw?()
      }
      await controller.loadTask?.value
      return redraws
    }
    let gate = Gate()
    await gate.open()
    let reader = reader(first: ["c", "a"], all: ["c", "a", "b"], heldAt: gate)
    // Loading and loaded, as before this step.
    #expect(await redraws(opening: small, reader: reader) == 2)
    // Loading, the first rows, loaded.
    #expect(await redraws(opening: big, reader: reader) == 3)
  }

  // MARK: A refresh

  /// A browser on `big`, which holds plain files with these names, loaded and
  /// watching. The reader and the watcher are stubs.
  private func watchedBrowser(holding names: [String], gate: Gate? = nil) async throws -> (
    controller: BrowserViewController, table: NSTableView, reader: StubReader,
    watcher: StubWatcher, answered: AnsweredSignals
  ) {
    let reader = StubReader(
      results: [big: names.map { file($0, in: big) }, small: [file("only.txt", in: small)]],
      gates: gate.map { [big: $0] } ?? [:])
    let watcher = StubWatcher()
    let controller = BrowserViewController(location: big, reader: reader, watcher: watcher)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    let answered = AnsweredSignals(of: controller.model)
    await gate?.open()
    await controller.loadTask?.value
    controller.startWatching()
    return (controller, table, reader, watcher, answered)
  }

  /// Changes what `big` holds and sends the signal a watch would, then waits
  /// for the browser to have dealt with it.
  private func refresh(
    _ reader: StubReader, to names: [String], _ watcher: StubWatcher, _ answered: AnsweredSignals
  ) async {
    let before = answered.count
    reader.changed.update { $0[big] = .items(names.map { file($0, in: big) }) }
    await watcher.send(to: big)
    await answered.wait(for: before + 1)
  }

  private func status(of controller: BrowserViewController) throws -> NSTextField {
    try #require(
      controller.view.subviews.first { $0.accessibilityIdentifier() == "browser-status" }
        as? NSTextField)
  }

  @Test func aRefreshThatAddsARowAboveTheSelectedOneKeepsTheSameItemSelected() async throws {
    let (controller, table, reader, watcher, answered) = try await watchedBrowser(
      holding: ["b", "c"])
    table.selectRowIndexes([1], byExtendingSelection: false)
    let selected = controller.model.selection
    try #require(selected.map(\.lastPathComponent) == ["c"])

    var selectionChanges = 0
    let observer = NotificationCenter.default.addObserver(
      forName: NSTableView.selectionDidChangeNotification, object: table, queue: nil
    ) { _ in
      MainActor.assumeIsolated { selectionChanges += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    await refresh(reader, to: ["a", "b", "c"], watcher, answered)
    #expect(rowNames(of: table) == ["a", "b", "c"])
    #expect(table.selectedRowIndexes == [2])
    // The table was told once, and the model's selection is the one it had.
    #expect(selectionChanges == 1)
    #expect(controller.model.selection == selected)
  }

  @Test func aRefreshKeepsTheScrollOffsetWithTheSelectedRowOutOfViewAndWithNothingSelected()
    async throws
  {
    for selectingTheFirstRow in [true, false] {
      let names = numberedNames(400)
      let (controller, table, reader, watcher, answered) = try await watchedBrowser(
        holding: names)
      let window = NSWindow(contentViewController: controller)
      window.layoutIfNeeded()
      let clipView = try #require(table.enclosingScrollView?.contentView)
      if selectingTheFirstRow {
        table.selectRowIndexes([0], byExtendingSelection: false)
      }

      table.scrollRowToVisible(300)
      let scrolled = clipView.bounds.origin
      try #require(scrolled.y > 0)
      try #require(!table.rows(in: table.visibleRect).contains(0))

      // Another row changes: the last file is gone.
      await refresh(reader, to: Array(names.dropLast()), watcher, answered)
      #expect(table.numberOfRows == 399)
      #expect(clipView.bounds.origin == scrolled)
      #expect(table.selectedRowIndexes == (selectingTheFirstRow ? [0] : []))
    }
  }

  @Test func keyboardFocusStaysWhereItIsThroughARefresh() async throws {
    for focusInTheList in [false, true] {
      let (controller, table, reader, watcher, answered) = try await watchedBrowser(
        holding: ["a", "b"])
      let (window, other) = window(holding: controller)
      let focused: NSResponder = focusInTheList ? table : other
      try #require(window.makeFirstResponder(focused))

      await refresh(reader, to: ["a", "b", "c"], watcher, answered)
      try #require(table.numberOfRows == 3)
      #expect(window.firstResponder === focused)
    }
  }

  @Test func aRefreshThatChangesNothingDoesNotReloadTheTable() async throws {
    let (controller, table, reader, watcher, answered) = try await watchedBrowser(
      holding: ["a", "b"])
    var redraws = 0
    let redraw = controller.model.onChange
    controller.model.onChange = {
      redraws += 1
      redraw?()
    }

    await refresh(reader, to: ["a", "b"], watcher, answered)
    #expect(reader.listings(of: big) == 2)
    #expect(redraws == 0)
    #expect(table.numberOfRows == 2)
  }

  @Test func theStatusTextFollowsAFolderThatIsEmptiedAndFilledByRefreshes() async throws {
    let (controller, table, reader, watcher, answered) = try await watchedBrowser(holding: [])
    let status = try status(of: controller)
    var hiddenAtEachRedraw: [Bool] = []
    let redraw = controller.model.onChange
    controller.model.onChange = {
      redraw?()
      hiddenAtEachRedraw.append(status.isHidden)
    }
    try #require(!status.isHidden && status.stringValue == "This folder is empty.")

    // Still empty: nothing is redrawn, so the text was never hidden.
    await refresh(reader, to: [], watcher, answered)
    #expect(hiddenAtEachRedraw == [])
    #expect(!status.isHidden)

    await refresh(reader, to: ["a"], watcher, answered)
    #expect(hiddenAtEachRedraw == [true])
    #expect(table.numberOfRows == 1)

    await refresh(reader, to: [], watcher, answered)
    #expect(hiddenAtEachRedraw == [true, false])
    #expect(status.stringValue == "This folder is empty.")
    #expect(table.numberOfRows == 0)
  }

  @Test func aFolderThatFailsOnARefreshShowsNoRowsAndTheReason() async throws {
    let (controller, table, reader, watcher, answered) = try await watchedBrowser(
      holding: ["a", "b"])
    let status = try status(of: controller)
    try #require(status.isHidden)

    reader.changed.update { $0[big] = .missing }
    await watcher.send(.folderChanged, to: big)
    await answered.wait(for: 1)
    #expect(table.numberOfRows == 0)
    #expect(!status.isHidden)
    #expect(status.stringValue == CocoaError(.fileReadNoSuchFile).localizedDescription)
  }

  @Test func openSentWhileARefreshIsHeldMovesToTheFolderAndEndsLoaded() async throws {
    let sub = big.appending(path: "Sub", directoryHint: .isDirectory)
    let gate = Gate()
    var reader = StubReader(
      results: [big: [FileItem(url: sub, kind: .directory)], sub: [file("inner.txt", in: sub)]],
      gates: [big: gate])
    reader.results[small] = []
    let watcher = StubWatcher()
    let controller = BrowserViewController(location: big, reader: reader, watcher: watcher)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    let answered = AnsweredSignals(of: controller.model)
    await gate.open()
    await controller.loadTask?.value
    controller.startWatching()

    await gate.close()
    await watcher.send(to: big)
    await gate.waitUntilReached()
    table.selectRowIndexes([0], byExtendingSelection: false)
    controller.openSelection(nil)
    await controller.loadTask?.value
    #expect(controller.model.location == sub)
    #expect(controller.model.state == .loaded)
    #expect(rowNames(of: table) == ["inner.txt"])
    #expect(watcher.watched == [sub])

    // The held refresh of the folder that was left changes nothing.
    await gate.open()
    await answered.wait(for: 1)
    #expect(controller.model.location == sub)
    #expect(rowNames(of: table) == ["inner.txt"])
  }

  @Test func backSentTwiceWhileARefreshIsHeldEndsOnThePreviousFolderLoaded() async throws {
    let gate = Gate()
    let reader = StubReader(
      results: [small: [file("only.txt", in: small)], big: [file("a", in: big)]],
      gates: [big: gate])
    let watcher = StubWatcher()
    let controller = BrowserViewController(location: small, reader: reader, watcher: watcher)
    let table = try #require(Self.firstSubview(of: NSTableView.self, in: controller.view))
    let answered = AnsweredSignals(of: controller.model)
    await controller.loadTask?.value
    controller.startWatching()
    await gate.open()
    await controller.model.navigate(to: big)
    try #require(controller.model.canGoBack)

    await gate.close()
    await watcher.send(to: big)
    await gate.waitUntilReached()
    // No await between the two: the first one's task has not started.
    controller.goBack(nil)
    controller.goBack(nil)
    await controller.loadTask?.value
    #expect(controller.model.state == .loaded)
    #expect(controller.model.location == small)
    #expect(rowNames(of: table) == ["only.txt"])

    await gate.open()
    await answered.wait(for: 1)
    #expect(controller.model.location == small)
    #expect(rowNames(of: table) == ["only.txt"])
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

/// A view that can hold keyboard focus, standing in for a control outside the browser.
private final class FocusableView: NSView {
  override var acceptsFirstResponder: Bool { true }
}
