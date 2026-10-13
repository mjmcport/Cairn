import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct SidebarModelTests {
  private func favorite(_ name: String, at path: String?) -> ResolvedFavorite {
    ResolvedFavorite(
      id: name, name: name, url: path.map { URL(filePath: $0, directoryHint: .isDirectory) })
  }

  private func build(
    favorites: [ResolvedFavorite] = [], volumes: [VolumeInfo] = [], cloud: [CloudFolder] = [],
    tags: [TagInfo] = []
  ) -> [SidebarSectionContent] {
    SidebarBuilder.sections(favorites: favorites, volumes: volumes, cloud: cloud, tags: tags)
  }

  @Test func recentsAreTheFirstFavoriteAndTheOnlyItemOfAnOtherwiseEmptySidebar() {
    let sections = build()
    #expect(sections.map(\.section) == [.favorites])
    #expect(sections[0].items.map(\.title) == ["Recents"])
    #expect(sections[0].items[0].kind == .recents)
    #expect(VirtualLocation(url: sections[0].items[0].location) == .recents)
    #expect(!sections[0].items[0].canRemove)
  }

  @Test func sectionsComeInTheirFixedOrderAndEmptyOnesAreLeftOut() {
    let sections = build(
      favorites: [favorite("Docs", at: "/Users/x/Docs")],
      volumes: [VolumeInfo(url: URL(filePath: "/"), name: "Macintosh HD", isEjectable: false)],
      tags: [TagInfo(name: "Red", count: 2)])
    #expect(sections.map(\.section) == [.favorites, .locations, .tags])
    #expect(sections[0].items.map(\.title) == ["Recents", "Docs"])
    #expect(sections[0].items[1].canRemove)
  }

  @Test func aFavoriteWhoseFolderIsGoneIsKeptAndMarked() {
    let sections = build(favorites: [favorite("Gone", at: nil)])
    let item = sections[0].items[1]
    #expect(item.title == "Gone")
    #expect(item.isMissing)
    #expect(item.canRemove)
  }

  @Test func onlyEjectableVolumesGetTheEjectButton() {
    let sections = build(volumes: [
      VolumeInfo(url: URL(filePath: "/"), name: "Macintosh HD", isEjectable: false),
      VolumeInfo(url: URL(filePath: "/Volumes/Backup"), name: "Backup", isEjectable: true),
    ])
    let locations = sections.first { $0.section == .locations }?.items ?? []
    #expect(locations.map(\.title) == ["Macintosh HD", "Backup"])
    #expect(locations.map(\.canEject) == [false, true])
    #expect(locations.map(\.kind) == [.volume, .volume])
  }

  @Test func iCloudDriveComesFirstInCloudAndTheRestAreInNameOrder() {
    let sections = build(cloud: [
      CloudFolder(url: URL(filePath: "/c/Dropbox"), name: "Dropbox"),
      CloudFolder(url: URL(filePath: "/c/Box"), name: "Box"),
      CloudFolder(url: URL(filePath: "/c/iCloud"), name: "iCloud Drive", isICloudDrive: true),
    ])
    let cloud = sections.first { $0.section == .cloud }?.items ?? []
    #expect(cloud.map(\.title) == ["iCloud Drive", "Box", "Dropbox"])
  }

  @Test func tagsAreInNameOrderAndEachIsAVirtualLocation() {
    let sections = build(tags: [TagInfo(name: "Work", count: 1), TagInfo(name: "Red", count: 5)])
    let tags = sections.first { $0.section == .tags }?.items ?? []
    #expect(tags.map(\.title) == ["Red", "Work"])
    #expect(tags.map { VirtualLocation(url: $0.location) } == [.tag("Red"), .tag("Work")])
  }

  @Test func idsAreStableAcrossRebuilds() {
    let volumes = [VolumeInfo(url: URL(filePath: "/Volumes/A"), name: "A", isEjectable: true)]
    let first = build(volumes: volumes).flatMap(\.items).map(\.id)
    let second = build(volumes: volumes).flatMap(\.items).map(\.id)
    #expect(first == second)
    #expect(Set(first).count == first.count)
  }
}

@Suite struct FavoritesTests {
  private final class Violations: @unchecked Sendable {
    private var stored: [MainThreadGuard.Violation] = []
    private let lock = NSLock()
    var all: [MainThreadGuard.Violation] { lock.withLock { stored } }
    func record(_ violation: MainThreadGuard.Violation) {
      lock.withLock { stored.append(violation) }
    }
  }

  private func canonical(_ url: URL?) -> String? {
    url?.resolvingSymlinksInPath().path
  }

  @Test func aBookmarkFollowsAFolderThatWasRenamed() async throws {
    let tree = try FixtureTree.build { FixtureNode.directory("Projects") }
    defer { try? tree.remove() }
    let record = try Favorites.record(for: tree.url("Projects"))
    #expect(record.name == "Projects")

    let renamed = tree.root.appending(path: "Work", directoryHint: .isDirectory)
    try FileManager.default.moveItem(at: tree.url("Projects"), to: renamed)

    let resolved = Favorites.resolve([record])
    #expect(resolved.count == 1)
    #expect(canonical(resolved[0].url) == canonical(renamed))
    #expect(resolved[0].name == "Projects", "The name it was given is kept")
  }

  @Test func aFolderThatIsGoneIsKeptWithNoURL() async throws {
    let tree = try FixtureTree.build { FixtureNode.directory("Temp") }
    defer { try? tree.remove() }
    let record = try Favorites.record(for: tree.url("Temp"))
    try FileManager.default.removeItem(at: tree.url("Temp"))

    let resolved = Favorites.resolve([record])
    #expect(resolved.map(\.id) == [record.id])
    #expect(resolved[0].url == nil)
  }

  @Test func theStoreKeepsRecordsAcrossInstancesAndTellsNeverSavedFromEmpty() throws {
    let suite = "cairn.tests.favorites.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(UserDefaultsFavoriteStore(defaults: defaults).load() == nil)
    let records = [
      FavoriteRecord(id: "a", bookmark: Data([1, 2]), name: "A"),
      FavoriteRecord(id: "b", bookmark: Data([3]), name: "B"),
    ]
    UserDefaultsFavoriteStore(defaults: defaults).save(records)
    #expect(UserDefaultsFavoriteStore(defaults: defaults).load() == records)

    UserDefaultsFavoriteStore(defaults: defaults).save([])
    #expect(
      UserDefaultsFavoriteStore(defaults: defaults).load() == [],
      "Removing all is not 'never saved'")
  }

  @Test func theDefaultsStartWithHomeAndOnlyListFoldersThatExist() async throws {
    let records = Favorites.defaults()
    #expect(records.first?.name == "Home")
    let resolved = Favorites.resolve(records)
    #expect(resolved.allSatisfy { $0.url != nil })
  }

  @Test @MainActor func everyEntryPointTripsTheGuardOnTheMainThread() {
    func trips(_ entryPoint: String, _ body: () -> Void) {
      let violations = Violations()
      MainThreadGuard.withHandler(violations.record, perform: body)
      #expect(
        violations.all.contains { $0.entryPoint.hasPrefix(entryPoint) },
        "\(entryPoint) did not trip the guard")
    }
    trips("record") {
      _ = try? Favorites.record(for: FileManager.default.homeDirectoryForCurrentUser)
    }
    trips("resolve") { _ = Favorites.resolve([]) }
    trips("defaults") { _ = Favorites.defaults() }
    trips("volumes") { _ = SystemVolumeSource().volumes() }
    trips("folders") { _ = SystemCloudSource().folders() }
  }
}

@Suite struct SidebarSourcesTests {
  @Test func cloudListsICloudDriveAndEachFolderUnderCloudStorage() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Library") {
        FixtureNode.directory("CloudStorage") {
          FixtureNode.directory("Dropbox-Acme")
          FixtureNode.directory("GoogleDrive-me@example.com")
          FixtureNode.file("stray.txt")
        }
        FixtureNode.directory("Mobile Documents") {
          FixtureNode.directory("com~apple~CloudDocs")
        }
      }
    }
    defer { try? tree.remove() }

    let folders = SystemCloudSource(home: tree.root).folders()
    #expect(folders.first?.isICloudDrive == true)
    #expect(folders.first?.name == "iCloud Drive")
    let others = folders.dropFirst().map(\.name).sorted()
    #expect(others == ["Dropbox – Acme", "GoogleDrive – me@example.com"])
    #expect(folders.count == 3, "A file in CloudStorage is not a service folder")
  }

  @Test func cloudIsEmptyWhenNothingIsSetUp() async throws {
    let tree = try FixtureTree.build { FixtureNode.directory("Library") }
    defer { try? tree.remove() }
    #expect(SystemCloudSource(home: tree.root).folders().isEmpty)
  }

  @Test func volumesIncludeTheStartupDiskFirst() async {
    let volumes = SystemVolumeSource().volumes()
    #expect(volumes.first?.url.path == "/")
    #expect(volumes.first?.isEjectable == false)
  }
}
