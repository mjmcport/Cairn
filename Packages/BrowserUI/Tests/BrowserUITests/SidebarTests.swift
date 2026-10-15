import AppKit
import FileSystemCore
import Foundation
import TestSupport
import Testing

@testable import BrowserUI

/// Sources with canned answers.
private struct StubVolumes: VolumeSource {
  let list: Recorded<[VolumeInfo]>
  func volumes() -> [VolumeInfo] { list.value }
}

private struct StubCloud: CloudSource {
  var list: [CloudFolder] = []
  func folders() -> [CloudFolder] { list }
}

private struct StubTags: TagSource {
  var list: [TagInfo] = []
  func tags() async -> [TagInfo] { list }
}

private final class MemoryFavorites: FavoriteStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [FavoriteRecord]?
  init(_ records: [FavoriteRecord]? = []) { stored = records }
  func load() -> [FavoriteRecord]? { lock.withLock { stored } }
  func save(_ records: [FavoriteRecord]) { lock.withLock { stored = records } }
}

/// Reports each eject it was asked for, and can be made to fail.
private struct StubEjector: VolumeEjecting {
  let asked = Recorded<[URL]>([])
  let failing: Bool
  let events: AsyncStream<URL>.Continuation

  struct Refused: Error, LocalizedError {
    var errorDescription: String? { "The volume is busy." }
  }

  func eject(_ volume: URL) async throws {
    asked.update { $0.append(volume) }
    events.yield(volume)
    if failing { throw Refused() }
  }
}

@Suite @MainActor struct SidebarTests {
  private let backup = VolumeInfo(
    url: URL(filePath: "/Volumes/Backup", directoryHint: .isDirectory), name: "Backup",
    isEjectable: true)
  private let other = VolumeInfo(
    url: URL(filePath: "/Volumes/Photos", directoryHint: .isDirectory), name: "Photos",
    isEjectable: true)
  private let startup = VolumeInfo(
    url: URL(filePath: "/", directoryHint: .isDirectory), name: "Macintosh HD", isEjectable: false)

  private struct Harness {
    let sidebar: SidebarViewController
    let favorites: MemoryFavorites
    let volumes: Recorded<[VolumeInfo]>
    let ejector: StubEjector
    let ejects: AsyncStream<URL>
    let failures: Recorded<[String]>
  }

  private func harness(
    records: [FavoriteRecord]? = [], volumes: [VolumeInfo] = [], cloud: [CloudFolder] = [],
    tags: [TagInfo] = [], failingEject: Bool = false
  ) async -> Harness {
    let favorites = MemoryFavorites(records)
    let volumeList = Recorded(volumes)
    let (stream, continuation) = AsyncStream<URL>.makeStream()
    let ejector = StubEjector(failing: failingEject, events: continuation)
    let sidebar = SidebarViewController(
      favoriteStore: favorites, volumeSource: StubVolumes(list: volumeList),
      cloudSource: StubCloud(list: cloud), tagSource: StubTags(list: tags), ejector: ejector)
    let failures = Recorded<[String]>([])
    sidebar.presentFailure = { text in failures.update { $0.append(text) } }
    _ = sidebar.view
    sidebar.view.frame = NSRect(x: 0, y: 0, width: 220, height: 500)
    await sidebar.refresh()
    return Harness(
      sidebar: sidebar, favorites: favorites, volumes: volumeList, ejector: ejector,
      ejects: stream, failures: failures)
  }

  private func outline(of sidebar: SidebarViewController) throws -> NSOutlineView {
    let scroll = try #require(sidebar.view as? NSScrollView)
    return try #require(scroll.documentView as? NSOutlineView)
  }

  private func row(
    titled title: String, in outline: NSOutlineView, of sidebar: SidebarViewController
  )
    throws -> Int
  {
    for row in 0..<outline.numberOfRows {
      guard
        let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
      else { continue }
      if cell.textField?.stringValue == title { return row }
    }
    throw Missing(title: title)
  }

  private struct Missing: Error { let title: String }

  // MARK: What it lists

  @Test func listsRecentsFirstAndEachSectionInOrder() async {
    let h = await harness(
      volumes: [startup, backup],
      cloud: [
        CloudFolder(url: URL(filePath: "/c/iCloud"), name: "iCloud Drive", isICloudDrive: true)
      ],
      tags: [TagInfo(name: "Red", count: 1)])
    #expect(h.sidebar.sections.map(\.section) == [.favorites, .locations, .cloud, .tags])
    #expect(h.sidebar.sections[0].items.map(\.title) == ["Recents"])
    #expect(h.sidebar.sections[1].items.map(\.title) == ["Macintosh HD", "Backup"])
  }

  @Test func theViewAndItsRowsAreNamed() async throws {
    let h = await harness(volumes: [startup, backup])
    let outline = try outline(of: h.sidebar)
    #expect(outline.accessibilityIdentifier() == "sidebar")
    #expect(outline.accessibilityLabel() == "Sidebar")

    let backupRow = try row(titled: "Backup", in: outline, of: h.sidebar)
    let cell = try #require(
      outline.view(atColumn: 0, row: backupRow, makeIfNecessary: true) as? NSTableCellView)
    #expect(cell.textField?.accessibilityIdentifier() == "sidebar-item")
    let buttons = cell.subviews.compactMap { $0 as? NSButton }
    #expect(buttons.map { $0.accessibilityLabel() } == ["Eject Backup"])
    #expect(buttons.map { $0.accessibilityIdentifier() } == ["eject-button"])
  }

  @Test func onlyEjectableRowsShowTheEjectButton() async throws {
    let h = await harness(volumes: [startup, backup])
    let outline = try outline(of: h.sidebar)
    func buttonIsShown(_ title: String) throws -> Bool {
      let row = try row(titled: title, in: outline, of: h.sidebar)
      let cell = try #require(
        outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
      return cell.subviews.contains { ($0 as? NSButton).map { !$0.isHidden } ?? false }
    }
    #expect(try buttonIsShown("Backup"))
    #expect(try !buttonIsShown("Macintosh HD"))
    #expect(try !buttonIsShown("Recents"))
  }

  @Test func aFavoriteWhoseFolderIsGoneIsSpokenAsNotFound() async throws {
    let tree = try FixtureTree.build { FixtureNode.directory("Temp") }
    defer { try? tree.remove() }
    let record = try await Task.detached { try Favorites.record(for: tree.url("Temp")) }.value
    try FileManager.default.removeItem(at: tree.url("Temp"))

    let h = await harness(records: [record])
    let outline = try outline(of: h.sidebar)
    let row = try row(titled: "Temp", in: outline, of: h.sidebar)
    let cell = try #require(
      outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
    #expect(cell.textField?.accessibilityLabel() == "Temp, not found")
  }

  // MARK: Choosing and following

  @Test func choosingAnItemReportsItAndFollowingDoesNot() async throws {
    let h = await harness(volumes: [startup, backup])
    let outline = try outline(of: h.sidebar)
    let chosen = Recorded<[String]>([])
    h.sidebar.onChoose = { item, _ in chosen.update { $0.append(item.title) } }

    // The tab moved: the sidebar follows without choosing.
    h.sidebar.select(location: backup.url)
    #expect(chosen.value.isEmpty)
    #expect(h.sidebar.selectedItem?.title == "Backup")

    // A click is a choice.
    let row = try row(titled: "Macintosh HD", in: outline, of: h.sidebar)
    outline.selectRowIndexes([row], byExtendingSelection: false)
    #expect(chosen.value == ["Macintosh HD"])
  }

  @Test func theSidebarSelectsNothingForAPlaceItDoesNotHave() async {
    let h = await harness(volumes: [startup, backup])
    h.sidebar.select(location: backup.url)
    #expect(h.sidebar.selectedItem != nil)
    h.sidebar.select(location: URL(filePath: "/Users/nobody", directoryHint: .isDirectory))
    #expect(h.sidebar.selectedItem == nil)
  }

  @Test func theSelectionSurvivesARefresh() async {
    let h = await harness(volumes: [startup, backup])
    h.sidebar.select(location: backup.url)
    h.volumes.value = [startup, backup, other]
    await h.sidebar.refresh()
    #expect(h.sidebar.selectedItem?.title == "Backup")
    #expect(h.sidebar.sections[1].items.map(\.title) == ["Macintosh HD", "Backup", "Photos"])
  }

  @Test func aMountAndAnUnmountChangeTheLocations() async {
    let h = await harness(volumes: [startup])
    #expect(h.sidebar.sections.first { $0.section == .locations }?.items.count == 1)
    h.volumes.value = [startup, backup]
    await h.sidebar.refresh()
    #expect(
      h.sidebar.sections.first { $0.section == .locations }?.items.map(\.title) == [
        "Macintosh HD", "Backup",
      ])
    h.volumes.value = [startup]
    await h.sidebar.refresh()
    #expect(
      h.sidebar.sections.first { $0.section == .locations }?.items.map(\.title) == ["Macintosh HD"])
  }

  // MARK: Favorites

  @Test func addingAFolderKeepsItAndRemovingItForgetsIt() async throws {
    let tree = try FixtureTree.build { FixtureNode.directory("Projects") }
    defer { try? tree.remove() }
    let h = await harness()
    #expect(h.sidebar.sections[0].items.map(\.title) == ["Recents"])

    await h.sidebar.addFavorite(tree.url("Projects"))
    #expect(h.sidebar.sections[0].items.map(\.title) == ["Recents", "Projects"])
    #expect(h.favorites.load()?.map(\.name) == ["Projects"])

    // Adding the same folder again changes nothing.
    await h.sidebar.addFavorite(tree.url("Projects"))
    #expect(h.favorites.load()?.count == 1)

    let item = try #require(h.sidebar.sections[0].items.last)
    await h.sidebar.remove(item)
    #expect(h.sidebar.sections[0].items.map(\.title) == ["Recents"])
    #expect(h.favorites.load() == [])
  }

  @Test func recentsAndVolumesCannotBeRemoved() async {
    let h = await harness(volumes: [backup])
    for item in h.sidebar.sections.flatMap(\.items) {
      await h.sidebar.remove(item)
    }
    #expect(h.sidebar.sections.flatMap(\.items).count == 2)
    #expect(h.favorites.load() == [])
  }

  // MARK: Eject

  @Test func pressingTheEjectButtonOfOneOfTwoVolumesAsksForThatOne() async throws {
    let h = await harness(volumes: [startup, backup, other])
    let outline = try outline(of: h.sidebar)
    let row = try row(titled: "Photos", in: outline, of: h.sidebar)
    let cell = try #require(
      outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
    let button = try #require(cell.subviews.compactMap { $0 as? NSButton }.first)

    button.performClick(nil)
    for await asked in h.ejects.prefix(1) {
      #expect(asked == other.url)
    }
    #expect(h.ejector.asked.value == [other.url])
  }

  @Test func aFailedEjectSaysWhyAndLeavesTheVolumeListed() async {
    let h = await harness(volumes: [startup, backup], failingEject: true)
    let item = h.sidebar.sections[1].items[1]
    await h.sidebar.eject(item)
    #expect(h.failures.value == ["Backup could not be ejected. The volume is busy."])
    #expect(h.sidebar.sections[1].items.map(\.title) == ["Macintosh HD", "Backup"])
  }

  @Test func aSuccessfulEjectIsGoneOnceTheSystemSaysSo() async {
    let h = await harness(volumes: [startup, backup])
    let item = h.sidebar.sections[1].items[1]
    // The system reports the volume gone as the eject returns.
    h.volumes.value = [startup]
    await h.sidebar.eject(item)
    #expect(h.sidebar.sections[1].items.map(\.title) == ["Macintosh HD"])
    #expect(h.failures.value.isEmpty)
  }

  @Test func nothingIsEjectedByRefreshingOrChoosing() async throws {
    let h = await harness(volumes: [startup, backup])
    await h.sidebar.refresh()
    h.sidebar.select(location: backup.url)
    let outline = try outline(of: h.sidebar)
    outline.selectRowIndexes(
      [try row(titled: "Backup", in: outline, of: h.sidebar)], byExtendingSelection: false)
    #expect(h.ejector.asked.value.isEmpty)
  }

  @Test func aVolumeThatCannotBeEjectedIsNeverAsked() async {
    let h = await harness(volumes: [startup])
    await h.sidebar.eject(h.sidebar.sections[1].items[0])
    #expect(h.ejector.asked.value.isEmpty)
  }
}
