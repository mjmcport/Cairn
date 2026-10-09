import Foundation
import Testing

@testable import TestSupport

/// Every test reads the property back with a system call, not through the
/// builder, so a builder bug cannot hide behind its own accessors.
@Suite struct FixtureTreeTests {
  // MARK: Read-back helpers

  private func status(_ path: String) throws -> stat {
    var info = stat()
    try #require(lstat(path, &info) == 0, "lstat failed for \(path): errno \(errno)")
    return info
  }

  private func extendedAttribute(_ name: String, at path: String) -> Data? {
    let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
    guard size >= 0 else { return nil }
    var data = Data(count: size)
    let read = data.withUnsafeMutableBytes {
      getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW)
    }
    return read == size ? data : nil
  }

  /// Names in a folder as raw bytes from `readdir`, without `.` and `..`.
  private func entryNames(in path: String) throws -> [String] {
    let directory = try #require(opendir(path))
    defer { closedir(directory) }
    var names: [String] = []
    while let entry = readdir(directory) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
          String(cString: $0)
        }
      }
      if name != "." && name != ".." { names.append(name) }
    }
    return names
  }

  private func kind(_ info: stat) -> mode_t { info.st_mode & S_IFMT }

  // MARK: Files

  @Test func writesFileContentsAndSizes() throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("empty.txt")
      FixtureNode.file("hello.txt", contents: Data("hello".utf8))
      FixtureNode.file("sized.bin", size: 3_000_000)
    }
    defer { try? tree.remove() }

    #expect(try status(tree.path("empty.txt")).st_size == 0)
    #expect(try Data(contentsOf: tree.url("hello.txt")) == Data("hello".utf8))

    let sized = try status(tree.path("sized.bin"))
    #expect(sized.st_size == 3_000_000)
    #expect(kind(sized) == S_IFREG)
    // Fully written: the blocks on disk cover the logical size.
    #expect(Int(sized.st_blocks) * 512 >= 3_000_000)
  }

  @Test func sparseFileHasALargeLogicalSizeAndAlmostNoBlocks() throws {
    let logicalSize = 1 << 30
    let tree = try FixtureTree.build {
      FixtureNode.sparseFile("sparse.img", size: logicalSize)
    }
    defer { try? tree.remove() }

    let info = try status(tree.path("sparse.img"))
    #expect(Int(info.st_size) == logicalSize)
    #expect(Int(info.st_blocks) * 512 < 1 << 20)
  }

  @Test func hiddenFilesUseADotNameOrTheHiddenFlag() throws {
    let tree = try FixtureTree.build {
      FixtureNode.hiddenFile("config")
      FixtureNode.hiddenFile(".already-dotted")
      FixtureNode.file("flagged.txt").hiddenFlag()
      FixtureNode.file("visible.txt")
    }
    defer { try? tree.remove() }

    let names = try entryNames(in: tree.path(""))
    #expect(names.contains(".config"))
    #expect(names.contains(".already-dotted"))
    #expect(try status(tree.path("flagged.txt")).st_flags & UInt32(UF_HIDDEN) != 0)
    #expect(try status(tree.path("visible.txt")).st_flags & UInt32(UF_HIDDEN) == 0)
  }

  // MARK: Folders, links and bundles

  @Test func buildsNestedFolders() throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("a") {
        FixtureNode.directory("b") {
          FixtureNode.file("deep.txt", contents: Data("x".utf8))
        }
        FixtureNode.directory("empty")
      }
    }
    defer { try? tree.remove() }

    #expect(kind(try status(tree.path("a/b"))) == S_IFDIR)
    #expect(try status(tree.path("a/b/deep.txt")).st_size == 1)
    #expect(try entryNames(in: tree.path("a/empty")).isEmpty)
  }

  @Test func symlinkStoresItsDestinationVerbatim() throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("target.txt", contents: Data("t".utf8))
      FixtureNode.symlink("relative", to: "target.txt")
      FixtureNode.symlink("dangling", to: "missing/nowhere")
      FixtureNode.directory("sub") {
        FixtureNode.symlink("up", to: "../target.txt")
      }
    }
    defer { try? tree.remove() }

    func destination(_ relativePath: String) throws -> String {
      var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
      let length = readlink(tree.path(relativePath), &buffer, buffer.count - 1)
      try #require(length >= 0)
      return String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    #expect(kind(try status(tree.path("relative"))) == S_IFLNK)
    #expect(try destination("relative") == "target.txt")
    #expect(try destination("dangling") == "missing/nowhere")
    #expect(try destination("sub/up") == "../target.txt")
    // The relative link in a subfolder resolves to the real file.
    #expect(try Data(contentsOf: tree.url("sub/up")) == Data("t".utf8))
  }

  @Test func hardLinkSharesAnInodeEvenWhenListedBeforeItsTarget() throws {
    let tree = try FixtureTree.build {
      FixtureNode.hardLink("second-name.txt", to: "folder/original.txt")
      FixtureNode.directory("folder") {
        FixtureNode.file("original.txt", contents: Data("shared".utf8))
      }
    }
    defer { try? tree.remove() }

    let original = try status(tree.path("folder/original.txt"))
    let linked = try status(tree.path("second-name.txt"))
    #expect(original.st_ino == linked.st_ino)
    #expect(original.st_nlink == 2)
    #expect(kind(linked) == S_IFREG)
  }

  @Test func bundleIsAPackageWithAnInfoPlistAndAnExecutable() throws {
    let tree = try FixtureTree.build {
      FixtureNode.bundle("Sample")
      FixtureNode.directory("Plain")
    }
    defer { try? tree.remove() }

    #expect(kind(try status(tree.path("Sample.app"))) == S_IFDIR)
    #expect(try status(tree.path("Sample.app/Contents/Info.plist")).st_size > 0)
    #expect(try status(tree.path("Sample.app/Contents/MacOS/Sample")).st_mode & 0o777 == 0o755)

    let bundle = try tree.url("Sample.app").resourceValues(forKeys: [.isPackageKey])
    let plain = try tree.url("Plain").resourceValues(forKeys: [.isPackageKey])
    #expect(bundle.isPackage == true)
    #expect(plain.isPackage == false)
  }

  // MARK: Attributes

  @Test func setsExtendedAttributes() throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("a.txt")
        .extendedAttribute("com.mjmcport.cairn.test", Data([0, 1, 2, 255]))
        .extendedAttribute("com.mjmcport.cairn.empty", Data())
      FixtureNode.directory("folder").extendedAttribute("com.mjmcport.cairn.dir", Data("d".utf8))
    }
    defer { try? tree.remove() }

    #expect(
      extendedAttribute("com.mjmcport.cairn.test", at: tree.path("a.txt")) == Data([0, 1, 2, 255]))
    #expect(extendedAttribute("com.mjmcport.cairn.empty", at: tree.path("a.txt")) == Data())
    #expect(extendedAttribute("com.mjmcport.cairn.dir", at: tree.path("folder")) == Data("d".utf8))
    #expect(extendedAttribute("com.mjmcport.cairn.absent", at: tree.path("a.txt")) == nil)
  }

  @Test func setsFinderTags() throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("tagged.txt").tagged("Red\n6", "Project X")
      FixtureNode.file("plain.txt")
    }
    defer { try? tree.remove() }

    // Finder stores tags as a binary property list in this attribute.
    let name = "com.apple.metadata:_kMDItemUserTags"
    let raw = try #require(extendedAttribute(name, at: tree.path("tagged.txt")))
    let stored = try #require(
      try PropertyListSerialization.propertyList(from: raw, format: nil) as? [String])
    #expect(
      stored.map { $0.split(separator: "\n").first.map(String.init) } == ["Red", "Project X"])
    #expect(extendedAttribute(name, at: tree.path("plain.txt")) == nil)
  }

  @Test func setsTheQuarantineFlag() throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("download.dmg").quarantined()
      FixtureNode.file("local.txt")
    }
    defer { try? tree.remove() }

    let raw = try #require(extendedAttribute("com.apple.quarantine", at: tree.path("download.dmg")))
    let fields = String(decoding: raw, as: UTF8.self).split(separator: ";")
    #expect(fields.count == 4)
    #expect(fields.first == "0081")
    #expect(extendedAttribute("com.apple.quarantine", at: tree.path("local.txt")) == nil)
  }

  @Test func setsPermissionsAndStillRemovesALockedTree() throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("private.txt").permissions(0o600)
      FixtureNode.file("read-only.txt").permissions(0o444)
      FixtureNode.directory("locked") {
        FixtureNode.file("inside.txt")
        FixtureNode.directory("inner") {
          FixtureNode.file("deep.txt")
        }.permissions(0o000)
      }.permissions(0o500)
    }

    #expect(try status(tree.path("private.txt")).st_mode & 0o777 == 0o600)
    #expect(try status(tree.path("read-only.txt")).st_mode & 0o777 == 0o444)
    #expect(try status(tree.path("locked")).st_mode & 0o777 == 0o500)
    #expect(try status(tree.path("locked/inner")).st_mode & 0o777 == 0o000)

    try tree.remove()
    var info = stat()
    #expect(lstat(tree.path(""), &info) != 0)
  }

  // MARK: Names

  @Test func preservesUnicodeNamesByteForByte() throws {
    let tree = try FixtureTree.build {
      for name in FixtureNames.unicode {
        FixtureNode.file(name)
      }
    }
    defer { try? tree.remove() }

    let onDisk = try entryNames(in: tree.path("")).map { Array($0.utf8) }
    #expect(onDisk.count == FixtureNames.unicode.count)
    for name in FixtureNames.unicode {
      #expect(onDisk.contains(Array(name.utf8)), "\(name.debugDescription) changed on disk")
    }
  }

  @Test func acceptsTheLongestNameAndRejectsALongerOne() throws {
    let longest = FixtureNames.long()
    #expect(longest.utf8.count == 255)

    let tree = try FixtureTree.build {
      FixtureNode.file(longest)
    }
    defer { try? tree.remove() }
    #expect(try entryNames(in: tree.path("")) == [longest])

    #expect(throws: FixtureError.self) {
      try FixtureTree.build {
        FixtureNode.file(FixtureNames.long(utf8Length: 256))
      }
    }
  }

  @Test func numberedNamesSortInCreationOrder() {
    #expect(FixtureNames.numbered(0) == "file-000000.txt")
    #expect(FixtureNames.numbered(99_999, prefix: "img", extension: "png") == "img099999.png")
    let names = (0..<1_000).map { FixtureNames.numbered($0) }
    #expect(names == names.sorted())
  }

  // MARK: Large folders

  @Test(arguments: [10_000, 100_000])
  func buildsALargeFolder(count: Int) throws {
    let clock = ContinuousClock()
    var built: FixtureTree?
    let elapsed = try clock.measure {
      built = try FixtureTree.build {
        FixtureNode.files(count: count, in: "Big")
      }
    }
    let tree = try #require(built)
    defer { try? tree.remove() }

    let names = try entryNames(in: tree.path("Big"))
    #expect(names.count == count)
    #expect(Set(names).count == count)
    #expect(names.contains(FixtureNames.numbered(count - 1)))
    print("Built a \(count)-item folder in \(elapsed)")
  }

  // MARK: Failure and cleanup

  @Test func aFailedBuildLeavesNothingBehind() throws {
    let marker = "first-\(UUID().uuidString).txt"
    #expect(throws: FixtureError.self) {
      try FixtureTree.build {
        FixtureNode.file(marker)
        FixtureNode.hardLink("broken", to: "does-not-exist.txt")
      }
    }
    // The root's name is not known after a failure, so look for the marker in
    // every fixture folder. Other tests add and remove folders meanwhile.
    let temporary = FileManager.default.temporaryDirectory
    let fixtures = try FileManager.default.contentsOfDirectory(atPath: temporary.path)
      .filter { $0.hasPrefix("CairnFixture-") }
    for name in fixtures {
      let contents =
        (try? FileManager.default.contentsOfDirectory(atPath: temporary.appending(path: name).path))
        ?? []
      #expect(!contents.contains(marker))
    }
  }

  @Test func duplicateNamesFailInsteadOfOverwriting() {
    #expect(throws: FixtureError.self) {
      try FixtureTree.build {
        FixtureNode.file("same.txt", contents: Data("one".utf8))
        FixtureNode.file("same.txt", contents: Data("two".utf8))
      }
    }
  }
}
