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
