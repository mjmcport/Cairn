import Foundation

/// One entry in a fixture tree: a file, a folder, a link or a run of numbered
/// files. Build nodes with the static functions, then refine them with the
/// modifiers:
///
/// ```swift
/// let tree = try FixtureTree.build {
///   FixtureNode.file("notes.txt", size: 1_024).tagged("Red").permissions(0o600)
///   FixtureNode.directory("Projects") {
///     FixtureNode.sparseFile("disk.img", size: 1 << 30)
///     FixtureNode.symlink("latest", to: "disk.img")
///   }
///   FixtureNode.files(count: 10_000, in: "Big")
/// }
/// ```
public struct FixtureNode: Sendable {
  enum Content: Sendable {
    case file(Data)
    case sizedFile(Int)
    case sparseFile(Int)
    case directory([FixtureNode])
    case symlink(destination: String)
    case hardLink(target: String)
  }

  /// The properties applied after the node exists on disk.
  struct Attributes: Sendable {
    var extendedAttributes: [String: Data] = [:]
    var tags: [String] = []
    var isQuarantined = false
    var hasHiddenFlag = false
    var permissions: mode_t?

    var isEmpty: Bool {
      extendedAttributes.isEmpty && tags.isEmpty && !isQuarantined && !hasHiddenFlag
        && permissions == nil
    }
  }

  let name: String
  let content: Content
  var attributes = Attributes()

  // MARK: Nodes

  /// A file with the given contents (empty by default).
  public static func file(_ name: String, contents: Data = Data()) -> FixtureNode {
    FixtureNode(name: name, content: .file(contents))
  }

  /// A file of exactly `size` bytes, all written to disk.
  public static func file(_ name: String, size: Int) -> FixtureNode {
    FixtureNode(name: name, content: .sizedFile(size))
  }

  /// A file whose logical size is `size` bytes but which occupies almost no
  /// disk space, for testing large files cheaply.
  public static func sparseFile(_ name: String, size: Int) -> FixtureNode {
    FixtureNode(name: name, content: .sparseFile(size))
  }

  /// A file whose name starts with a dot, which Finder hides.
  public static func hiddenFile(_ name: String, contents: Data = Data()) -> FixtureNode {
    FixtureNode(name: name.hasPrefix(".") ? name : "." + name, content: .file(contents))
  }

  /// A folder holding the nodes that `children` lists.
  public static func directory(
    _ name: String,
    @FixtureBuilder _ children: () -> [FixtureNode] = { [] }
  ) -> FixtureNode {
    FixtureNode(name: name, content: .directory(children()))
  }

  /// A symbolic link. `destination` is stored as given, so a relative
  /// destination resolves from the link's own folder. It need not exist.
  public static func symlink(_ name: String, to destination: String) -> FixtureNode {
    FixtureNode(name: name, content: .symlink(destination: destination))
  }

  /// A second name for an existing file.
  /// - Parameter target: The file's path relative to the root of the tree.
  public static func hardLink(_ name: String, to target: String) -> FixtureNode {
    FixtureNode(name: name, content: .hardLink(target: target))
  }

  /// An application bundle: a folder the system shows as a single file.
  /// - Parameter name: The bundle's name; `.app` is added if it is missing.
  public static func bundle(_ name: String) -> FixtureNode {
    let bundleName = name.hasSuffix(".app") ? name : name + ".app"
    let executable = String(bundleName.dropLast(4))
    let infoPlist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleIdentifier</key><string>com.mjmcport.cairn.fixture</string>
        <key>CFBundleName</key><string>\(executable)</string>
        <key>CFBundleExecutable</key><string>\(executable)</string>
        <key>CFBundlePackageType</key><string>APPL</string>
      </dict>
      </plist>
      """
    return .directory(bundleName) {
      FixtureNode.directory("Contents") {
        FixtureNode.file("Info.plist", contents: Data(infoPlist.utf8))
        FixtureNode.directory("MacOS") {
          FixtureNode.file(executable, contents: Data("#!/bin/sh\n".utf8)).permissions(0o755)
        }
      }
    }
  }

  /// A folder holding `count` empty files named `prefix000000.ext` upward,
  /// for testing large folders.
  public static func files(
    count: Int,
    in directoryName: String,
    prefix: String = "file-",
    extension pathExtension: String = "txt"
  ) -> FixtureNode {
    .directory(directoryName) {
      for index in 0..<count {
        FixtureNode.file(FixtureNames.numbered(index, prefix: prefix, extension: pathExtension))
      }
    }
  }

  // MARK: Modifiers

  /// Sets an extended attribute.
  public func extendedAttribute(_ name: String, _ value: Data) -> FixtureNode {
    var node = self
    node.attributes.extendedAttributes[name] = value
    return node
  }

  /// Sets Finder tags. A name may carry a color as Finder stores it, for
  /// example `"Red\n6"`.
  public func tagged(_ tags: String...) -> FixtureNode {
    var node = self
    node.attributes.tags = tags
    return node
  }

  /// Marks the item as downloaded, as a browser would.
  public func quarantined() -> FixtureNode {
    var node = self
    node.attributes.isQuarantined = true
    return node
  }

  /// Sets the BSD hidden flag, which hides an item whose name has no dot.
  public func hiddenFlag() -> FixtureNode {
    var node = self
    node.attributes.hasHiddenFlag = true
    return node
  }

  /// Sets the POSIX permission bits, for example `0o600`.
  public func permissions(_ mode: mode_t) -> FixtureNode {
    var node = self
    node.attributes.permissions = mode
    return node
  }
}

/// Collects the nodes listed in a fixture closure.
@resultBuilder
public enum FixtureBuilder {
  public static func buildExpression(_ node: FixtureNode) -> [FixtureNode] { [node] }
  public static func buildExpression(_ nodes: [FixtureNode]) -> [FixtureNode] { nodes }
  public static func buildBlock(_ parts: [FixtureNode]...) -> [FixtureNode] { parts.flatMap { $0 } }
  public static func buildOptional(_ part: [FixtureNode]?) -> [FixtureNode] { part ?? [] }
  public static func buildEither(first part: [FixtureNode]) -> [FixtureNode] { part }
  public static func buildEither(second part: [FixtureNode]) -> [FixtureNode] { part }
  public static func buildArray(_ parts: [[FixtureNode]]) -> [FixtureNode] { parts.flatMap { $0 } }
}

/// Names that file managers commonly get wrong.
public enum FixtureNames {
  /// Names in several scripts, with precomposed and decomposed accents, an
  /// emoji sequence and leading and trailing spaces. No two are equal under
  /// Unicode normalization, so all can share one folder.
  public static let unicode: [String] = [
    "caf\u{E9}.txt",  // precomposed e-acute
    "re\u{301}sume\u{301}.txt",  // decomposed e-acute
    "日本語のファイル.txt",
    "ملف عربي.txt",
    "Ελληνικά.txt",
    "👩‍👩‍👧‍👦 family.txt",
    " leading space.txt",
    "trailing space ",
    "new\nline.txt",
  ]

  /// The longest file name APFS accepts: 255 UTF-8 bytes.
  public static let maximumUTF8Length = 255

  /// A name of exactly `utf8Length` UTF-8 bytes.
  public static func long(utf8Length: Int = maximumUTF8Length, extension ext: String = "txt")
    -> String
  {
    let suffix = "." + ext
    return String(repeating: "n", count: max(0, utf8Length - suffix.utf8.count)) + suffix
  }

  /// The name ``FixtureNode/files(count:in:prefix:extension:)`` gives file `index`.
  public static func numbered(_ index: Int, prefix: String = "file-", extension ext: String = "txt")
    -> String
  {
    let digits = String(index)
    let padding = String(repeating: "0", count: max(0, 6 - digits.count))
    return "\(prefix)\(padding)\(digits).\(ext)"
  }
}
