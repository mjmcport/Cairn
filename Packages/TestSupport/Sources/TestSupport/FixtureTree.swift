import Foundation

/// A failed system call while building or removing a fixture.
public struct FixtureError: Error, CustomStringConvertible, Sendable {
  public let call: String
  public let path: String
  public let code: Int32

  public var description: String {
    "\(call) failed for \(path): \(String(cString: strerror(code))) (\(code))"
  }
}

/// A temporary folder tree built from a declarative description, for tests to
/// read. See ``FixtureNode`` for what a tree can hold.
///
/// Call ``remove()`` when the test ends. It restores permissions first, so a
/// tree with unreadable folders is still deleted.
public struct FixtureTree: Sendable {
  /// The folder that holds the tree's top-level nodes.
  public let root: URL

  private let nodes: [FixtureNode]

  /// Builds a tree in a new folder under the system temporary directory.
  public static func build(@FixtureBuilder _ nodes: () -> [FixtureNode]) throws -> FixtureTree {
    let directory = try TemporaryDirectory(prefix: "CairnFixture")
    // Resolve /var to /private/var so paths compare equal to what the system reports.
    let root = directory.url.resolvingSymlinksInPath()
    let tree = FixtureTree(root: root, nodes: nodes())
    do {
      try tree.create()
    } catch {
      try? tree.remove()
      throw error
    }
    return tree
  }

  /// The location of an item, given its path relative to the root.
  public func url(_ relativePath: String) -> URL {
    root.appending(path: relativePath)
  }

  /// The file-system path of an item, given its path relative to the root.
  public func path(_ relativePath: String) -> String {
    url(relativePath).path(percentEncoded: false)
  }

  /// Deletes the tree.
  public func remove() throws {
    restorePermissions(of: nodes, in: root.path(percentEncoded: false))
    try FileManager.default.removeItem(at: root)
  }

  // MARK: Building

  private func create() throws {
    let rootPath = root.path(percentEncoded: false)
    // Links come second so a hard link can name a file listed after it, and
    // attributes come last so a read-only folder can still be filled.
    try createContents(of: nodes, in: rootPath)
    try createLinks(of: nodes, in: rootPath)
    try applyAttributes(of: nodes, in: rootPath)
  }

  private func createContents(of nodes: [FixtureNode], in directory: String) throws {
    for node in nodes {
      let path = directory + "/" + node.name
      switch node.content {
      case .file(let data):
        try writeFile(at: path, data: data)
      case .sizedFile(let size):
        try writeFile(at: path, size: size)
      case .sparseFile(let size):
        let descriptor = try openNewFile(at: path)
        defer { close(descriptor) }
        guard ftruncate(descriptor, off_t(size)) == 0 else {
          throw FixtureError(call: "ftruncate", path: path, code: errno)
        }
      case .directory(let children):
        guard mkdir(path, 0o755) == 0 else {
          throw FixtureError(call: "mkdir", path: path, code: errno)
        }
        try createContents(of: children, in: path)
      case .symlink, .hardLink:
        break
      }
    }
  }

  private func createLinks(of nodes: [FixtureNode], in directory: String) throws {
    for node in nodes {
      let path = directory + "/" + node.name
      switch node.content {
      case .symlink(let destination):
        guard symlink(destination, path) == 0 else {
          throw FixtureError(call: "symlink", path: path, code: errno)
        }
      case .hardLink(let target):
        guard link(self.path(target), path) == 0 else {
          throw FixtureError(call: "link", path: path, code: errno)
        }
      case .directory(let children):
        try createLinks(of: children, in: path)
      case .file, .sizedFile, .sparseFile:
        break
      }
    }
  }

  private func applyAttributes(of nodes: [FixtureNode], in directory: String) throws {
    for node in nodes {
      let path = directory + "/" + node.name
      if case .directory(let children) = node.content {
        try applyAttributes(of: children, in: path)
      }
      let attributes = node.attributes
      guard !attributes.isEmpty else { continue }

      for (name, value) in attributes.extendedAttributes {
        try setExtendedAttribute(name, value, at: path)
      }
      if !attributes.tags.isEmpty {
        do {
          try (URL(filePath: path) as NSURL).setResourceValue(
            attributes.tags, forKey: .tagNamesKey)
        } catch {
          throw FixtureError(
            call: "setResourceValue(tagNames)", path: path,
            code: Int32((error as NSError).code))
        }
      }
      if attributes.isQuarantined {
        // flags;hex timestamp;agent name;event UUID, as LaunchServices writes it.
        let timestamp = String(Int(Date().timeIntervalSince1970), radix: 16)
        let value = "0081;\(timestamp);Cairn Fixture;\(UUID().uuidString)"
        try setExtendedAttribute("com.apple.quarantine", Data(value.utf8), at: path)
      }
      if attributes.hasHiddenFlag {
        guard lchflags(path, UInt32(UF_HIDDEN)) == 0 else {
          throw FixtureError(call: "lchflags", path: path, code: errno)
        }
      }
      if let permissions = attributes.permissions {
        guard lchmod(path, permissions) == 0 else {
          throw FixtureError(call: "lchmod", path: path, code: errno)
        }
      }
    }
  }

  /// Makes every node with custom permissions writable again, top down, so
  /// the tree can be walked and deleted.
  private func restorePermissions(of nodes: [FixtureNode], in directory: String) {
    for node in nodes {
      let path = directory + "/" + node.name
      guard case .directory(let children) = node.content else { continue }
      if node.attributes.permissions != nil {
        chmod(path, 0o755)
      }
      restorePermissions(of: children, in: path)
    }
  }

  // MARK: System calls

  private func openNewFile(at path: String) throws -> Int32 {
    let descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard descriptor >= 0 else {
      throw FixtureError(call: "open", path: path, code: errno)
    }
    return descriptor
  }

  private func writeFile(at path: String, data: Data) throws {
    let descriptor = try openNewFile(at: path)
    defer { close(descriptor) }
    try writeAll(data, to: descriptor, path: path)
  }

  private func writeFile(at path: String, size: Int) throws {
    let descriptor = try openNewFile(at: path)
    defer { close(descriptor) }
    // A repeating, non-zero pattern, so the file is never stored as a hole.
    let chunk = Data(
      (0..<min(max(size, 1), 1 << 20)).map { UInt8(truncatingIfNeeded: $0 % 251 + 1) })
    var remaining = size
    while remaining > 0 {
      let count = min(remaining, chunk.count)
      try writeAll(chunk.prefix(count), to: descriptor, path: path)
      remaining -= count
    }
  }

  private func writeAll(_ data: Data, to descriptor: Int32, path: String) throws {
    try data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
        guard written >= 0 else {
          throw FixtureError(call: "write", path: path, code: errno)
        }
        offset += written
      }
    }
  }

  private func setExtendedAttribute(_ name: String, _ value: Data, at path: String) throws {
    let result = value.withUnsafeBytes { buffer in
      setxattr(path, name, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
    }
    guard result == 0 else {
      throw FixtureError(call: "setxattr(\(name))", path: path, code: errno)
    }
  }
}
