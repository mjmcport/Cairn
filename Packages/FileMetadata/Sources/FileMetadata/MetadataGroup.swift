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
