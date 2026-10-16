import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// A saved tab brought back to a place that exists
/// (plans/phase-1a-step-10-state-restoration.md, U4: R14, R14a).
@Suite struct RestoredLocationTests {
  private struct Folders: FolderChecking {
    let existing: Set<String>
    func isListableFolder(_ url: URL) -> Bool {
      existing.contains(url.path(percentEncoded: false).trimmingSuffix("/"))
    }
  }

  private struct Tags: TagSource {
    let names: [String]
    func tags() async -> [TagInfo] { names.map { TagInfo(name: $0, count: 1) } }
  }

  private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

  private func resolver(existing: Set<String>, tags: [String] = []) -> RestoredLocation {
    RestoredLocation(home: home, folders: Folders(existing: existing), tags: Tags(names: tags))
  }

  private func url(_ path: String) -> String {
    URL(filePath: path, directoryHint: .isDirectory).absoluteString
  }

  @Test func aFolderThatExistsIsKeptWithEverythingSaved() async {
    var tab = SavedTab(location: url("/a/b"), selection: ["file:///a/b/f"], back: [])
    tab.openFolders = [["x"]]
    let result = await resolver(existing: ["/", "/a", "/a/b"]).resolve(tab)
    #expect(result == tab)
  }

  @Test func aRemovedFolderBecomesItsNearestExistingAncestor() async {
    let tab = SavedTab(
      location: url("/a/b/c/d"), openFolders: [["x"]], selection: ["file:///a/b/c/d/f"])
    let result = await resolver(existing: ["/", "/a", "/a/b"]).resolve(tab)
    #expect(result.location == URL(filePath: "/a/b", directoryHint: .isDirectory).absoluteString)
    // What belonged to the folder that is gone is dropped.
    #expect(result.selection.isEmpty)
    #expect(result.openFolders.isEmpty)
  }

  @Test func theViewAndSortSurviveTheMove() async {
    let tab = SavedTab(
      location: url("/gone"), viewMode: .icons,
      sort: SavedSort(key: .size, ascending: false), showsHidden: true)
    let result = await resolver(existing: ["/"]).resolve(tab)
    #expect(result.viewMode == .icons)
    #expect(result.sort == tab.sort)
    #expect(result.showsHidden)
    #expect(result.location == URL(filePath: "/", directoryHint: .isDirectory).absoluteString)
  }

  @Test func withNothingLeftTheTabOpensHome() async {
    let result = await resolver(existing: []).resolve(SavedTab(location: url("/a/b")))
    #expect(result.location == home.absoluteString)
  }

  @Test func aLocationThatCannotBeReadOpensHome() async {
    let result = await resolver(existing: ["/"]).resolve(SavedTab(location: ""))
    #expect(result.location == home.absoluteString)
  }

  @Test func aRemovedTagFallsBackToHomeAndAKnownTagStays() async {
    let gone = SavedTab(location: VirtualLocation.tag("Red").url.absoluteString)
    let kept = SavedTab(location: VirtualLocation.tag("Blue").url.absoluteString)
    let resolver = resolver(existing: ["/"], tags: ["Blue"])
    #expect(await resolver.resolve(gone).location == home.absoluteString)
    #expect(await resolver.resolve(kept) == kept)
  }

  @Test func recentsAlwaysStays() async {
    let tab = SavedTab(location: VirtualLocation.recents.url.absoluteString)
    #expect(await resolver(existing: []).resolve(tab) == tab)
  }

  @Test func historyEntriesThatAreGoneAreDroppedSoBackSkipsThem() async {
    let tab = SavedTab(
      location: url("/a"),
      back: [
        SavedHistoryEntry(location: url("/a/old")),
        SavedHistoryEntry(location: url("/b")),
        SavedHistoryEntry(location: VirtualLocation.tag("Red").url.absoluteString),
      ],
      forward: [SavedHistoryEntry(location: url("/c")), SavedHistoryEntry(location: url("/b"))])
    let result = await resolver(existing: ["/", "/a", "/b"]).resolve(tab)
    #expect(result.back.map(\.location) == [url("/b")])
    #expect(result.forward.map(\.location) == [url("/b")])
  }

  @Test func theWalkUpEndsAtTheRootWhateverTheSpelling() async {
    // `..` above the root and a doubled slash must not loop.
    let result = await resolver(existing: ["/"]).resolve(
      SavedTab(location: "file:///../../x//y/"))
    #expect(result.location == URL(filePath: "/", directoryHint: .isDirectory).absoluteString)
  }

  @Test func theDiskCheckerFindsTheNearestRealAncestor() async throws {
    let base = FileManager.default.temporaryDirectory.appending(
      path: "RestoredLocationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let kept = base.appending(path: "kept", directoryHint: .isDirectory)
    let gone = kept.appending(path: "gone", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.removeItem(at: gone)

    let real = RestoredLocation(home: home, tags: Tags(names: []))
    let result = await real.resolve(SavedTab(location: gone.absoluteString))
    let resolved = try #require(URL(string: result.location))
    #expect(resolved.standardizedFileURL.path == kept.standardizedFileURL.path)
  }

  @Test @MainActor func theDiskCheckerTripsTheMainThreadGuardButResolveDoesNot() async {
    let tripped = Recorded<Int>(0)
    await MainThreadGuard.withHandler({ _ in tripped.update { $0 += 1 } }) {
      _ = DiskFolderChecker().isListableFolder(URL(filePath: "/"))
    }
    #expect(tripped.value == 1)

    tripped.update { $0 = 0 }
    let real = RestoredLocation(home: home, tags: Tags(names: []))
    await MainThreadGuard.withHandler({ _ in tripped.update { $0 += 1 } }) {
      _ = await real.resolve(SavedTab(location: "file:///definitely/not/here/"))
    }
    #expect(tripped.value == 0)
  }
}

extension String {
  fileprivate func trimmingSuffix(_ suffix: String) -> String {
    count > 1 && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
  }
}
