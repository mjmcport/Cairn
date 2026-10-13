import AppKit
import Foundation
import Testing

/// What `NSOutlineView` does when its data changes, asked of the system
/// rather than assumed (plans/phase-1a-step-05-list-view.md, KTD12 and
/// KTD18). The numbers are printed for the step's lessons note; the
/// assertions are the behaviors the list view is built on, so a change in
/// AppKit shows here before it shows as a bug.
///
/// A step 5 probe, kept: the same questions are asked on macOS 15, 26 and 27.
@Suite @MainActor struct OutlineBehaviorTests {
  /// A row handle with the identity of its path, so a new handle for the
  /// same row is the same row to the outline.
  private final class Node: NSObject {
    let key: [String]
    let isFolder: Bool

    init(_ key: [String], isFolder: Bool) {
      self.key = key
      self.isFolder = isFolder
    }

    override func isEqual(_ object: Any?) -> Bool {
      (object as? Node)?.key == key
    }

    override var hash: Int { key.hashValue }
  }

  private final class Source: NSObject, NSOutlineViewDataSource {
    var top: [Node] = []
    var children: [[String]: [Node]] = [:]

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
      guard let node = item as? Node else { return top.count }
      return children[node.key]?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
      guard let node = item as? Node else { return top[index] }
      return children[node.key]![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
      (item as? Node)?.isFolder ?? false
    }

    func outlineView(
      _ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?
    ) -> Any? {
      (item as? Node)?.key.last
    }
  }

  /// An outline in a window with `count` top-level rows, every tenth a
  /// folder holding three items.
  private struct Rig {
    let window: NSWindow
    let outline: NSOutlineView
    let scroll: NSScrollView
    let source: Source
  }

  private func rig(count: Int) -> Rig {
    let source = Source()
    source.top = Self.nodes(count: count, extra: 0)
    for node in source.top where node.isFolder {
      source.children[node.key] = (0..<3).map { Node(node.key + ["child\($0)"], isFolder: false) }
    }
    let outline = NSOutlineView()
    let column = NSTableColumn(identifier: .init(rawValue: "name"))
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.dataSource = source
    outline.allowsMultipleSelection = true
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    scroll.documentView = outline
    scroll.hasVerticalScroller = true
    let window = NSWindow(
      contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = scroll
    return Rig(window: window, outline: outline, scroll: scroll, source: source)
  }

  /// The top-level nodes, as new objects each time. `extra` rows are added
  /// above everything, as a change on disk can.
  private static func nodes(count: Int, extra: Int) -> [Node] {
    let added = (0..<extra).map { Node(["added\($0)"], isFolder: false) }
    return added
      + (0..<count).map { Node(["item\($0)"], isFolder: $0.isMultiple(of: 10)) }
  }

  /// Reloads and then does what drawing the list needs: asks how many rows
  /// there are, lays the view out and draws it. `reloadData()` alone may
  /// only mark the outline as stale.
  private func settle(_ rig: Rig, after work: () -> Void) -> Duration {
    elapsed {
      work()
      _ = rig.outline.numberOfRows
      rig.outline.layoutSubtreeIfNeeded()
      rig.window.displayIfNeeded()
    }
  }

  private func elapsed(_ work: () -> Void) -> Duration {
    let start = ContinuousClock.now
    work()
    return ContinuousClock.now - start
  }

  @Test(arguments: [10_000, 100_000])
  func aRootReloadKeepsTheScrollOffsetAndTheFirstResponder(count: Int) throws {
    let rig = rig(count: count)
    let initial = settle(rig) { rig.outline.reloadData() }
    rig.window.makeFirstResponder(rig.outline)

    let target = count / 2
    rig.outline.scrollRowToVisible(target)
    rig.outline.selectRowIndexes([target], byExtendingSelection: false)
    let origin = rig.scroll.contentView.bounds.origin

    // A refresh: every handle is a new object, and one row was added above.
    rig.source.top = Self.nodes(count: count, extra: 1)
    for node in rig.source.top where node.isFolder {
      rig.source.children[node.key] = (0..<3).map {
        Node(node.key + ["child\($0)"], isFolder: false)
      }
    }
    let reload = settle(rig) { rig.outline.reloadData() }
    let after = rig.scroll.contentView.bounds.origin

    print(
      "OutlineBehaviorTests: \(count) rows: first reload \(initial), refresh reload \(reload) "
        + "(with row count, layout and display); offset \(origin.y) -> \(after.y)")
    #expect(rig.scroll.contentView.bounds.origin == origin)
    #expect(rig.window.firstResponder === rig.outline)
  }

  @Test func aRootReloadKeepsOpenFoldersOpenWhenHandlesAreEqual() throws {
    let rig = rig(count: 1_000)
    rig.outline.reloadData()
    let folder = try #require(rig.source.top.first { $0.isFolder })
    rig.outline.expandItem(folder)
    #expect(rig.outline.isItemExpanded(folder))
    let rowsOpen = rig.outline.numberOfRows

    rig.source.top = Self.nodes(count: 1_000, extra: 0)
    for node in rig.source.top where node.isFolder {
      rig.source.children[node.key] = (0..<3).map {
        Node(node.key + ["child\($0)"], isFolder: false)
      }
    }
    rig.outline.reloadData()

    let reopened = try #require(rig.source.top.first { $0.isFolder })
    print(
      "OutlineBehaviorTests: after a root reload, open folder still open: "
        + "\(rig.outline.isItemExpanded(reopened)); rows \(rowsOpen) -> \(rig.outline.numberOfRows)"
    )
    #expect(rig.outline.numberOfRows == rowsOpen)
    #expect(rig.outline.isItemExpanded(reopened))
  }

  @Test func reloadingOneFolderLeavesTheRestOfTheListWhereItWas() throws {
    let rig = rig(count: 10_000)
    rig.outline.reloadData()
    let folder = try #require(rig.source.top.first { $0.isFolder })
    rig.outline.expandItem(folder)
    rig.window.makeFirstResponder(rig.outline)

    rig.outline.scrollRowToVisible(5_000)
    rig.outline.selectRowIndexes([5_000], byExtendingSelection: false)
    let origin = rig.scroll.contentView.bounds.origin
    let selectedItem = rig.outline.item(atRow: 5_000) as? Node

    rig.source.children[folder.key] = (0..<4).map {
      Node(folder.key + ["child\($0)"], isFolder: false)
    }
    let reload = settle(rig) { rig.outline.reloadItem(folder, reloadChildren: true) }
    let after = rig.scroll.contentView.bounds.origin

    print(
      "OutlineBehaviorTests: reloading one open folder took \(reload); "
        + "selected row now \(rig.outline.selectedRow) (was 5000, one row added above); "
        + "offset \(origin.y) -> \(after.y)")
    #expect(after == origin)
    #expect(rig.outline.selectedRow == 5_001)
    #expect(rig.window.firstResponder === rig.outline)
    // The row is still the same item, wherever it now sits.
    let selectedNow = rig.outline.item(atRow: rig.outline.selectedRow) as? Node
    #expect(selectedNow == selectedItem)
    #expect(rig.outline.isItemExpanded(folder))
  }
}
