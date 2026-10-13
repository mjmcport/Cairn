import AppKit
import FileSystemCore
import UniformTypeIdentifiers

/// The icon the system has for a kind of file, chosen from the item's kind
/// and the extension of its name. Nothing is read from the disk, so a cell
/// can have a picture at once; a better one replaces it when it arrives.
@MainActor
final class GenericIcons {
  private var cache: [String: NSImage] = [:]

  /// The content type a name and a kind stand for.
  static func contentType(for item: FileItem) -> UTType {
    switch item.kind {
    case .directory: return .folder
    case .package: return UTType(filenameExtension: item.url.pathExtension) ?? .package
    case .symbolicLink: return .symbolicLink
    case .file: return UTType(filenameExtension: item.url.pathExtension) ?? .data
    }
  }

  func icon(for item: FileItem) -> NSImage {
    let type = Self.contentType(for: item)
    if let cached = cache[type.identifier] { return cached }
    let icon = NSWorkspace.shared.icon(for: type)
    cache[type.identifier] = icon
    return icon
  }

  /// How many icons have been made, by type, for tests.
  var count: Int { cache.count }
}
