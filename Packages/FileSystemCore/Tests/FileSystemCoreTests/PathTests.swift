import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct PathCrumbsTests {
  @Test func crumbsRunFromTheRootDownAndTheLastIsCurrent() {
    let crumbs = PathCrumbs.crumbs(
      for: URL(filePath: "/Users/me/Docs", directoryHint: .isDirectory))
    #expect(crumbs.map(\.title) == ["Macintosh HD", "Users", "me", "Docs"])
    #expect(crumbs.map(\.isCurrent) == [false, false, false, true])
    #expect(crumbs[2].url.path == "/Users/me")
  }

  @Test func theRootAloneIsOneCrumbAndTakesTheGivenName() {
    let crumbs = PathCrumbs.crumbs(for: URL(filePath: "/"), rootName: "Disk")
    #expect(crumbs.map(\.title) == ["Disk"])
    #expect(crumbs[0].isCurrent)
  }

  @Test func aVirtualLocationIsOneCrumbWithNoFoldersAboveIt() {
    let tag = PathCrumbs.crumbs(for: VirtualLocation.tag("Red").url)
    #expect(tag.map(\.title) == ["Red"])
    let recents = PathCrumbs.crumbs(for: VirtualLocation.recents.url)
    #expect(recents.count == 1)
    #expect(recents[0].url == VirtualLocation.recents.url)
  }
}

@Suite struct PathFormatTests {
  private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

  @Test func eachFormatOfAPathWithASpace() {
    let url = URL(filePath: "/Users/me/My Folder/a b.txt")
    #expect(PathFormat.path.string(for: url, home: home) == "/Users/me/My Folder/a b.txt")
    #expect(
      PathFormat.escapedPath.string(for: url, home: home) == "/Users/me/My\\ Folder/a\\ b.txt")
    #expect(
      PathFormat.fileURL.string(for: url, home: home) == "file:///Users/me/My%20Folder/a%20b.txt")
    #expect(PathFormat.homeRelativePath.string(for: url, home: home) == "~/My Folder/a b.txt")
  }

  @Test func aFoldersClosingSlashIsLeftOffInEveryFormat() {
    let folder = URL(filePath: "/Users/me/My Folder", directoryHint: .isDirectory)
    #expect(PathFormat.path.string(for: folder, home: home) == "/Users/me/My Folder")
    #expect(PathFormat.escapedPath.string(for: folder, home: home) == "/Users/me/My\\ Folder")
    #expect(PathFormat.homeRelativePath.string(for: folder, home: home) == "~/My Folder")
    #expect(
      PathFormat.path.string(for: URL(filePath: "/", directoryHint: .isDirectory), home: home)
        == "/")
  }

  @Test func homeRelativeIsThePlainPathOutsideHomeAndATildeForHome() {
    #expect(
      PathFormat.homeRelativePath.string(for: URL(filePath: "/usr/bin"), home: home) == "/usr/bin")
    #expect(PathFormat.homeRelativePath.string(for: home, home: home) == "~")
    #expect(
      PathFormat.homeRelativePath.string(for: URL(filePath: "/Users/meow/x"), home: home)
        == "/Users/meow/x")
  }

  @Test func theShellEscapeCoversWhatAShellReadsAsMoreThanAName() {
    func escaped(_ name: String) -> String { PathFormat.shellEscape(name) }
    #expect(escaped("/a/it's") == "/a/it\\'s")
    #expect(escaped("/a/$HOME") == "/a/\\$HOME")
    #expect(escaped("/a/`id`") == "/a/\\`id\\`")
    #expect(escaped("/a/(x);y&z") == "/a/\\(x\\)\\;y\\&z")
    #expect(escaped("/a/é") == "/a/é")
    #expect(escaped("/a/b\nc") == "$'/a/b\\nc'")
    #expect(escaped("/a/b\\c") == "/a/b\\\\c")
  }

  @Test func everyFormatHasATitle() {
    #expect(PathFormat.allCases.map(\.title).count == 4)
    #expect(Set(PathFormat.allCases.map(\.title)).count == 4)
  }
}

@Suite struct TypedPathTests {
  private let base = URL(filePath: "/Users/me/Docs", directoryHint: .isDirectory)
  private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

  private func resolve(_ text: String) -> String {
    TypedPath.resolve(text, relativeTo: base, home: home).path
  }

  @Test func tildeAbsoluteRelativeAndDots() {
    #expect(resolve("~") == "/Users/me")
    #expect(resolve("~/Desktop") == "/Users/me/Desktop")
    #expect(resolve("/usr/bin") == "/usr/bin")
    #expect(resolve("sub/dir") == "/Users/me/Docs/sub/dir")
    #expect(resolve("../Pictures") == "/Users/me/Pictures")
    #expect(resolve("./x") == "/Users/me/Docs/x")
    #expect(resolve("/usr/local/") == "/usr/local")
    #expect(resolve("") == "/Users/me/Docs")
    #expect(resolve("  ~/x  ") == "/Users/me/x")
  }

  @Test func completionContextSplitsFolderAndTheNameBeingTyped() {
    func context(_ text: String) -> (String, String) {
      let result = TypedPath.completionContext(text, relativeTo: base, home: home)
      return (result.folder.path, result.prefix)
    }
    #expect(context("Do") == ("/Users/me/Docs", "Do"))
    #expect(context("~/Doc") == ("/Users/me", "Doc"))
    #expect(context("/usr/") == ("/usr", ""))
    #expect(context("~") == ("/Users/me", ""))
    #expect(context("../Pic") == ("/Users/me", "Pic"))
  }

  @Test func textForAFolderEndsInASlash() {
    #expect(TypedPath.text(for: URL(filePath: "/usr", directoryHint: .isDirectory)) == "/usr/")
    #expect(TypedPath.text(for: URL(filePath: "/")) == "/")
  }
}

@Suite struct FolderCompletionTests {
  private final class Violations: @unchecked Sendable {
    private var stored: [MainThreadGuard.Violation] = []
    private let lock = NSLock()
    var all: [MainThreadGuard.Violation] { lock.withLock { stored } }
    func record(_ violation: MainThreadGuard.Violation) {
      lock.withLock { stored.append(violation) }
    }
  }

  private func tree() throws -> FixtureTree {
    try FixtureTree.build {
      FixtureNode.directory("Documents")
      FixtureNode.directory("Downloads")
      FixtureNode.directory("Desktop")
      FixtureNode.directory("Music")
      FixtureNode.directory(".hidden")
      FixtureNode.file("Doc.txt")
      FixtureNode.bundle("Thing.app")
      FixtureNode.symlink("DocLink", to: "Documents")
    }
  }

  @Test func offersOnlyFoldersThatBeginWithThePrefixByName() throws {
    let tree = try tree()
    defer { try? tree.remove() }
    let found = try DirectoryFolderCompleter().folders(in: tree.root, prefix: "do", limit: 20)
    #expect(found.map(\.name) == ["DocLink", "Documents", "Downloads"])
  }

  @Test func hiddenFoldersAreOfferedOnlyForADot() throws {
    let tree = try tree()
    defer { try? tree.remove() }
    let completer = DirectoryFolderCompleter()
    #expect(
      try completer.folders(in: tree.root, prefix: "", limit: 20).map(\.name).contains(".hidden")
        == false)
    #expect(try completer.folders(in: tree.root, prefix: ".", limit: 20).map(\.name) == [".hidden"])
  }

  @Test func filesAndPackagesAreNotOffered() throws {
    let tree = try tree()
    defer { try? tree.remove() }
    let names = try DirectoryFolderCompleter().folders(in: tree.root, prefix: "", limit: 20).map(
      \.name)
    #expect(!names.contains("Doc.txt"))
    #expect(!names.contains("Thing.app"))
  }

  @Test func theLimitIsAppliedAfterTheSort() throws {
    let tree = try tree()
    defer { try? tree.remove() }
    let found = try DirectoryFolderCompleter().folders(in: tree.root, prefix: "", limit: 2)
    #expect(found.map(\.name) == ["Desktop", "DocLink"])
  }

  @Test func existenceTellsFolderFileAndMissing() throws {
    let tree = try tree()
    defer { try? tree.remove() }
    let completer = DirectoryFolderCompleter()
    #expect(completer.existence(of: tree.url("Documents")) == .folder)
    #expect(completer.existence(of: tree.url("Doc.txt")) == .file)
    #expect(completer.existence(of: tree.url("nope")) == .missing)
  }

  @Test func aBigFolderIsCompletedQuickly() throws {
    let tree = try FixtureTree.build {
      FixtureNode.files(count: 10_000, in: "Big")
    }
    defer { try? tree.remove() }
    let started = ContinuousClock.now
    let found = try DirectoryFolderCompleter().folders(
      in: tree.url("Big"), prefix: "file", limit: 20)
    let elapsed = ContinuousClock.now - started
    #expect(found.isEmpty)
    #expect(elapsed < .seconds(2), "Completing in 10,000 entries took \(elapsed)")
  }

  @Test @MainActor func everyEntryPointTripsTheGuardOnTheMainThread() {
    let completer = DirectoryFolderCompleter()
    let violations = Violations()
    MainThreadGuard.withHandler(violations.record) {
      _ = try? completer.folders(in: URL(filePath: "/"), prefix: "", limit: 1)
      _ = completer.existence(of: URL(filePath: "/"))
    }
    #expect(violations.all.count == 2)
  }
}
