import AppKit
import FileSystemCore
import Foundation
import TestSupport
import Testing

@testable import BrowserUI

@Suite @MainActor struct BrowserViewControllerTests {
  @Test func buildsAnIdentifiedLabelledListWithThreeColumns() throws {
    let controller = BrowserViewController(
      location: URL(filePath: "/tmp", directoryHint: .isDirectory))
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

  @Test func foldersShowDashesForSizeAndFilesShowAByteCount() {
    let folder = FileItem(url: URL(filePath: "/tmp/f"), kind: .directory)
    let file = FileItem(
      url: URL(filePath: "/tmp/a"), kind: .file, size: 2_000_000,
      modificationDate: Date(timeIntervalSince1970: 0))
    #expect(BrowserViewController.sizeText(for: folder) == "--")
    #expect(BrowserViewController.modifiedText(for: folder) == "--")
    #expect(
      BrowserViewController.sizeText(for: file)
        == Int64(2_000_000).formatted(.byteCount(style: .file)))
    #expect(BrowserViewController.modifiedText(for: file).contains("19"))
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
