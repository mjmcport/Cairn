import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The list as an outline: folders that open in place, rows that stay where
/// they are through a refresh, and the sort and type-to-select that come
/// with it (plans/phase-1a-step-05-list-view.md, U5). Real `NSOutlineView`
/// in a real window; the reader and the watcher are stubs, so nothing here
/// waits on a clock.
@Suite @MainActor struct OutlineViewTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }
  private var other: URL { root.appending(path: "Other", directoryHint: .isDirectory) }
  private var deep: URL { sub.appending(path: "Deep", directoryHint: .isDirectory) }

  private let subKey = FolderKey(names: ["Sub"])
  private let otherKey = FolderKey(names: ["Other"])
  private let deepKey = FolderKey(names: ["Sub", "Deep"])

  private func file(
    _ name: String, in folder: URL, size: Int64? = nil, onDisk: Int64? = nil,
    modified: TimeInterval? = nil, added: TimeInterval? = nil
  ) -> FileItem {
    FileItem(
      url: folder.appending(path: name), kind: .file, size: size,
      modificationDate: modified.map(Date.init(timeIntervalSince1970:)), allocatedSize: onDisk,
      dateAdded: added.map(Date.init(timeIntervalSince1970:)))
  }

  private func folder(_ name: String, in parent: URL) -> FileItem {
    FileItem(url: parent.appending(path: name, directoryHint: .isDirectory), kind: .directory)
  }

  private func listings() -> [URL: [FileItem]] {
    [
      root: [
        folder("Sub", in: root), folder("Other", in: root), file("a.txt", in: root, size: 5),
        file("m.txt", in: root, size: 50),
        FileItem(url: root.appending(path: "App.app"), kind: .package),
      ],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub), file("b.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
      other: [file("o.txt", in: other)],
    ]
  }

  @MainActor private struct Rig {
    let controller: BrowserViewController
    let window: NSWindow
    let outline: NSOutlineView
    let reader: StubReader
    let watcher: StubWatcher
    let answered: AnsweredSignals

    var model: BrowserModel { controller.model }
  }

  /// A browser in a window, on `root`, loaded and watching.
  private func rig(results: [URL: [FileItem]]? = nil, reader: StubReader? = nil) async throws -> Rig
  {
    let reader = reader ?? StubReader(results: results ?? listings())
    let watcher = StubWatcher()
    let controller = BrowserViewController(location: root, reader: reader, watcher: watcher)
    let answered = AnsweredSignals(of: controller.model)
    let window = NSWindow(contentViewController: controller)
    window.layoutIfNeeded()
    let outline = try #require(Self.firstSubview(of: NSOutlineView.self, in: controller.view))
    await controller.loadTask?.value
    controller.startWatching()
    return Rig(
      controller: controller, window: window, outline: outline, reader: reader, watcher: watcher,
      answered: answered)
  }

  private func nodes(of outline: NSOutlineView) -> [OutlineNode] {
    (0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? OutlineNode }
  }

  /// The visible rows by name, each indented by two spaces per level.
  private func rows(of outline: NSOutlineView) -> [String] {
    (0..<outline.numberOfRows).map { row in
      let node = outline.item(atRow: row) as? OutlineNode
      let name = node?.item?.name ?? node?.message ?? "?"
      return String(repeating: "  ", count: outline.level(forRow: row)) + name
    }
  }

  private func node(_ key: FolderKey, in outline: NSOutlineView) throws -> OutlineNode {
    try #require(nodes(of: outline).first { $0.key == key && !$0.isStatus })
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

  // MARK: The list is an outline

  @Test func theListIsAnIdentifiedLabelledOutlineWithFiveSortableColumns() async throws {
    let rig = try await rig()
    #expect(rig.outline.accessibilityIdentifier() == "file-list")
    #expect(rig.outline.accessibilityLabel() == "Files")
    #expect(
      rig.outline.tableColumns.map(\.title)
        == ["Name", "Size", "Size on Disk", "Date Modified", "Date Added"])
    #expect(rig.outline.outlineTableColumn === rig.outline.tableColumns.first)
    #expect(rig.outline.tableColumns.allSatisfy { $0.sortDescriptorPrototype != nil })
  }

  @Test func everyColumnFitsInTheWindowsDefaultWidth() async throws {
    let rig = try await rig()
    // The width the app gives its window: AppDelegate.
    rig.window.setContentSize(NSSize(width: 900, height: 600))
    rig.window.layoutIfNeeded()
    let outline = rig.outline
    let scroll = try #require(outline.enclosingScrollView)
    scroll.layoutSubtreeIfNeeded()

    let last = outline.rect(ofColumn: outline.numberOfColumns - 1)
    // A column that hangs outside the window is cut off, and the list grows a
    // horizontal scroller. Both showed up as contrast failures in the audit.
    #expect(last.maxX <= scroll.contentView.bounds.width + 0.5)
    #expect(outline.bounds.width <= scroll.contentView.bounds.width + 0.5)
  }

  @Test func onlyAFolderHasADisclosureTriangle() async throws {
    let rig = try await rig()
    for node in nodes(of: rig.outline) {
      let expandable = rig.outline.isExpandable(node)
      #expect(expandable == (node.item?.kind == .directory), "\(node.item?.name ?? "?")")
    }
    #expect(rows(of: rig.outline) == ["a.txt", "App.app", "m.txt", "Other", "Sub"])
  }

  // MARK: Opening in place

  @Test func openingAFolderFromTheModelShowsItsRowsIndentedBeneathIt() async throws {
    let rig = try await rig()
    #expect(rig.model.openFolder(subKey))
    await rig.model.waitForOpenFolders()

    #expect(
      rows(of: rig.outline)
        == ["a.txt", "App.app", "m.txt", "Other", "Sub", "  b.txt", "  Deep", "  x.txt"])
    #expect(rig.outline.level(forItem: try node(subKey.appending("b.txt"), in: rig.outline)) == 1)
    #expect(rig.outline.isItemExpanded(try node(subKey, in: rig.outline)))
  }

  @Test func theUserOpeningAFolderOpensItInTheModelWithoutMovingAnywhere() async throws {
    let rig = try await rig()
    let subNode = try node(subKey, in: rig.outline)

    rig.outline.expandItem(subNode)
    #expect(rig.model.isOpen(subKey))
    await rig.model.waitForOpenFolders()
    #expect(rows(of: rig.outline).contains("  x.txt"))
    #expect(rig.model.location == root)
    #expect(!rig.model.canGoBack)

    rig.outline.collapseItem(subNode)
    #expect(!rig.model.isOpen(subKey))
    #expect(!rows(of: rig.outline).contains("  x.txt"))
  }

  @Test func foldersStayOpenThroughARefreshOfTheTopLevelAndOfTheirOwnFolder() async throws {
    let rig = try await rig()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let before = rows(of: rig.outline)

    // The top level changes: a file is added.
    var top = listings()[root]!
    top.append(file("c.txt", in: root))
    rig.reader.changed.update { $0[root] = .items(top) }
    await rig.watcher.send(to: root)
    await rig.answered.wait(for: 1)
    #expect(rig.model.isOpen(subKey))
    #expect(rows(of: rig.outline).contains("  x.txt"))
    #expect(rows(of: rig.outline).count == before.count + 1)

    // The open folder changes.
    var inside = listings()[sub]!
    inside.append(file("y.txt", in: sub))
    rig.reader.changed.update { $0[sub] = .items(inside) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 2)
    #expect(rows(of: rig.outline).contains("  y.txt"))
    #expect(rig.model.isOpen(subKey))
  }

  @Test func aFolderOpenInsideAnOpenFolderIsIndentedAgain() async throws {
    let rig = try await rig()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    rig.model.openFolder(deepKey)
    await rig.model.waitForOpenFolders()
    #expect(rows(of: rig.outline).contains("    z.txt"))
    #expect(rig.outline.level(forItem: try node(deepKey.appending("z.txt"), in: rig.outline)) == 2)
  }

  // MARK: Selection, scroll and focus

  @Test func aSelectedRowInsideAnOpenFolderStaysTheSameItemWhenARowIsAddedAboveIt() async throws {
    let rig = try await rig()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let xKey = subKey.appending("x.txt")
    let row = rig.outline.row(forItem: try node(xKey, in: rig.outline))
    rig.outline.selectRowIndexes([row], byExtendingSelection: false)
    let selected = rig.model.selection
    try #require(selected == [sub.appending(path: "x.txt")])

    var top = listings()[root]!
    top.append(file("0-new.txt", in: root))
    rig.reader.changed.update { $0[root] = .items(top) }
    await rig.watcher.send(to: root)
    await rig.answered.wait(for: 1)

    #expect(rig.outline.selectedRowIndexes == [row + 1])
    #expect(rig.model.selection == selected)
  }

  @Test func aRefreshOfAnOpenFolderKeepsTheScrollOffsetTheSelectionAndTheFocus() async throws {
    var results = listings()
    results[root] = (0..<300).map { file("f\(String(format: "%03d", $0)).txt", in: root) }
    results[root]?.append(folder("Sub", in: root))
    let rig = try await rig(results: results)
    rig.window.setContentSize(NSSize(width: 800, height: 300))
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    rig.window.makeFirstResponder(rig.outline)
    let clip = try #require(rig.outline.enclosingScrollView?.contentView)

    // The selected row is far above what is in view, so a refresh that
    // scrolled to the selection would be seen.
    rig.outline.selectRowIndexes([20], byExtendingSelection: false)
    rig.outline.scrollRowToVisible(150)
    let origin = clip.bounds.origin
    let selected = rig.model.selection
    try #require(origin.y > 0 && selected.count == 1)

    var inside = listings()[sub]!
    inside.append(file("y.txt", in: sub))
    rig.reader.changed.update { $0[sub] = .items(inside) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)

    #expect(rows(of: rig.outline).contains("  y.txt"))
    #expect(clip.bounds.origin == origin)
    #expect(rig.window.firstResponder === rig.outline)
    #expect(rig.model.selection == selected)
    // The row selected is the same item at the same row: nothing above moved.
    #expect(rig.outline.selectedRowIndexes == [20])
  }

  @Test func closingAFolderWithAnItemSelectedInsideSelectsTheFolder() async throws {
    let rig = try await rig()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let xRow = rig.outline.row(forItem: try node(subKey.appending("x.txt"), in: rig.outline))
    rig.outline.selectRowIndexes([xRow], byExtendingSelection: false)

    rig.outline.collapseItem(try node(subKey, in: rig.outline))
    #expect(rig.model.selection == [sub])
    let subRow = rig.outline.row(forItem: try node(subKey, in: rig.outline))
    #expect(rig.outline.selectedRowIndexes == [subRow])
  }

  // MARK: Columns, sorting and folders first

  @Test func aMissingValueShowsDashesAndIsSpokenInWordsInEveryColumn() async throws {
    let rig = try await rig()
    let row = rig.outline.row(forItem: try node(subKey, in: rig.outline))
    let expected = [
      (1, "No size"), (2, "No size on disk"), (3, "No date"), (4, "No date added"),
    ]
    for (column, spoken) in expected {
      let cell = try #require(
        rig.outline.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)
      #expect(cell.textField?.stringValue == "--")
      #expect(cell.accessibilityLabel() == spoken)
      #expect(cell.textField?.accessibilityLabel() == spoken)
    }
  }

  @Test func sizeOnDiskAndDateAddedShowTheirValues() async throws {
    var results = listings()
    results[root] = [
      file("a.bin", in: root, size: 1_000_000, onDisk: 4_096, added: 0)
    ]
    let rig = try await rig(results: results)
    let sizeOnDisk = try #require(
      rig.outline.view(atColumn: 2, row: 0, makeIfNecessary: true) as? NSTableCellView)
    let added = try #require(
      rig.outline.view(atColumn: 4, row: 0, makeIfNecessary: true) as? NSTableCellView)
    #expect(sizeOnDisk.textField?.stringValue == Int64(4_096).formatted(.byteCount(style: .file)))
    #expect(added.textField?.stringValue.contains("19") == true)
  }

  @Test func clickingAHeaderSortsEveryLevelAndShowsTheIndicator() async throws {
    var results = listings()
    results[sub] = [
      file("big.bin", in: sub, size: 900), file("small.bin", in: sub, size: 1),
      file("mid.bin", in: sub, size: 50),
    ]
    let rig = try await rig(results: results)
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let xRow = rig.outline.row(forItem: try node(subKey.appending("mid.bin"), in: rig.outline))
    rig.outline.selectRowIndexes([xRow], byExtendingSelection: false)

    // What a click on the Size header does.
    rig.outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
    await rig.model.waitForOpenFolders()

    #expect(rig.model.sort.key == .size)
    #expect(!rig.model.sort.ascending)
    #expect(
      rows(of: rig.outline)
        == ["m.txt", "a.txt", "Sub", "  big.bin", "  mid.bin", "  small.bin", "Other", "App.app"])
    // The selected item is the same and is still selected.
    #expect(rig.model.selection == [sub.appending(path: "mid.bin")])
    let newRow = rig.outline.row(forItem: try node(subKey.appending("mid.bin"), in: rig.outline))
    #expect(rig.outline.selectedRowIndexes == [newRow])
    #expect(rig.outline.sortDescriptors.first?.key == "size")
    #expect(rig.outline.sortDescriptors.first?.ascending == false)
  }

  @Test func aHeaderClickKeepsFoldersOnTopWhenItIsOn() async throws {
    let rig = try await rig()
    rig.controller.toggleFoldersFirst(nil)
    await rig.model.waitForOpenFolders()
    try #require(rig.model.sort.foldersFirst)

    rig.outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
    await rig.model.waitForOpenFolders()
    #expect(rig.model.sort.key == .size)
    #expect(rig.model.sort.foldersFirst)
    #expect(Array(rows(of: rig.outline).prefix(3)) == ["Sub", "Other", "m.txt"])
  }

  @Test func theModelsSortIsShownInTheHeaderWhenItIsSetInCode() async throws {
    let rig = try await rig()
    rig.model.changeSort(to: FileItemSort(key: .dateAdded, ascending: false))
    await rig.model.waitForOpenFolders()
    #expect(rig.outline.sortDescriptors.first?.key == "added")
    #expect(rig.outline.sortDescriptors.first?.ascending == false)
  }

  @Test func keepFoldersOnTopGroupsFoldersAtEveryLevelAndIsCheckedInTheMenu() async throws {
    let rig = try await rig()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let item = NSMenuItem(
      title: "Keep Folders on Top", action: #selector(BrowserViewController.toggleFoldersFirst(_:)),
      keyEquivalent: "")
    #expect(rig.controller.validateUserInterfaceItem(item))
    #expect(item.state == .off)

    rig.controller.toggleFoldersFirst(nil)
    await rig.model.waitForOpenFolders()
    #expect(
      rows(of: rig.outline)
        == ["Other", "Sub", "  Deep", "  b.txt", "  x.txt", "a.txt", "App.app", "m.txt"])
    #expect(rig.controller.validateUserInterfaceItem(item))
    #expect(item.state == .on)

    rig.controller.toggleFoldersFirst(nil)
    await rig.model.waitForOpenFolders()
    #expect(!rig.model.sort.foldersFirst)
    #expect(rows(of: rig.outline).first == "a.txt")
  }

  // MARK: Type to select

  @Test func typingSelectsByNameAndAStatusRowIsNotFound() async throws {
    var results = listings()
    results[sub] = nil
    let rig = try await rig(results: results)
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()

    let top = try node(FolderKey(names: ["m.txt"]), in: rig.outline)
    #expect(
      rig.controller.outlineView(rig.outline, typeSelectStringFor: nil, item: top) == "m.txt")
    let status = try #require(nodes(of: rig.outline).first { $0.isStatus })
    #expect(rig.controller.outlineView(rig.outline, typeSelectStringFor: nil, item: status) == nil)
  }

  // MARK: A folder that cannot be listed

  @Test func aFolderThatCannotBeListedShowsAStatusRowThatIsNotSelectable() async throws {
    var results = listings()
    results[sub] = nil
    let rig = try await rig(results: results)
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()

    let statusRow = try #require(
      (0..<rig.outline.numberOfRows).first {
        (rig.outline.item(atRow: $0) as? OutlineNode)?.isStatus == true
      })
    #expect(rig.outline.level(forRow: statusRow) == 1)
    let reason = try #require(rig.model.failure(of: subKey))
    let cell = try #require(
      rig.outline.view(atColumn: 0, row: statusRow, makeIfNecessary: true) as? NSTableCellView)
    #expect(cell.textField?.stringValue == reason)
    #expect(
      !rig.controller.outlineView(
        rig.outline, shouldSelectItem: try #require(rig.outline.item(atRow: statusRow))))
    // Still open, so a later change can list it.
    #expect(rig.model.isOpen(subKey))
  }

  // MARK: Open and navigation

  @Test func openOnAFolderInsideAnOpenFolderEntersItAsAMove() async throws {
    let rig = try await rig()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let deepRow = rig.outline.row(forItem: try node(deepKey, in: rig.outline))
    rig.outline.selectRowIndexes([deepRow], byExtendingSelection: false)

    rig.controller.openSelection(nil)
    await rig.controller.loadTask?.value
    #expect(rig.model.location.lastPathComponent == "Deep")
    #expect(rig.model.canGoBack)
    #expect(rows(of: rig.outline) == ["z.txt"])
    #expect(rig.model.openFolders.isEmpty)
  }

  @Test func openOnAFileOrAPackageDoesNothing() async throws {
    let rig = try await rig()
    let row = rig.outline.row(forItem: try node(FolderKey(names: ["App.app"]), in: rig.outline))
    rig.outline.selectRowIndexes([row], byExtendingSelection: false)
    let item = NSMenuItem(
      title: "Open", action: #selector(BrowserViewController.openSelection(_:)), keyEquivalent: "")
    #expect(!rig.controller.validateUserInterfaceItem(item))
    rig.controller.openSelection(nil)
    #expect(rig.model.location == root)
  }
}
