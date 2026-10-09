import FileSystemCore
import Foundation

/// A change to the file system that the operation engine can run, report
/// progress for and, where ``isUndoable`` is true, reverse.
public enum FileOperation: Sendable, Hashable {
  case copy(sources: [URL], destination: URL)
  case move(sources: [URL], destination: URL)
  case trash(items: [URL])
  case rename(item: URL, newName: String)
  case newFolder(parent: URL, name: String)

  /// The items the operation reads or changes.
  public var sources: [URL] {
    switch self {
    case .copy(let sources, _), .move(let sources, _): sources
    case .trash(let items): items
    case .rename(let item, _): [item]
    case .newFolder: []
    }
  }

  /// Whether the undo journal records the operation. A copy is not undoable:
  /// reversing it would delete files, which the user does through Trash.
  public var isUndoable: Bool {
    switch self {
    case .move, .trash, .rename, .newFolder: true
    case .copy: false
    }
  }
}
