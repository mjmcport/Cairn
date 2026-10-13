import CoreGraphics
import FileSystemCore
import Foundation

/// Makes the picture of a file: its thumbnail where the system can draw one,
/// otherwise the icon the system has for it.
///
/// A provider never takes a decision about whether a file may be read. A file
/// that is online only is not given to one: the caller checks
/// ``FileItem/isOnlineOnly`` first, because drawing a file can make the
/// system download it.
public protocol ThumbnailProviding: Sendable {
  /// The picture of `file` at a size in points and a display scale, or nil
  /// when none can be made. Never runs on the main thread. A cancelled call
  /// stops the work and returns nil.
  func thumbnail(for file: URL, pointSize: CGSize, scale: CGFloat) async -> CGImage?
}
