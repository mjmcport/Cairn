import FileSystemCore
import Foundation

/// The groups Get Info shows, in display order. Each group is read on demand,
/// so listing a folder never pays for metadata nobody is looking at.
public enum MetadataGroup: String, Sendable, CaseIterable {
  case general
  case sizes
  case dates
  case identity
  case permissions
  case tags
  case provenance
  case cloudState
  case volume
}

/// The metadata the list view needs for every row.
public struct BasicMetadata: Sendable, Hashable {
  /// The logical size in bytes, or `nil` for a folder.
  public let size: Int64?
  public let modificationDate: Date?

  public init(size: Int64?, modificationDate: Date?) {
    self.size = size
    self.modificationDate = modificationDate
  }
}
