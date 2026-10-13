import FileSystemCore
import Foundation

/// The handle an `NSOutlineView` holds for one row.
///
/// AppKit needs a class instance for each item, and needs it to stay equal
/// to itself across a reload so that a folder that was open is still open.
/// A node therefore has the identity of its key, never of its content: the
/// item it carries is whatever the model listed last and is replaced in
/// place by the controller.
final class OutlineNode: NSObject {
  /// The item's place under the folder being shown. A status row has the
  /// key of the folder it speaks for.
  let key: FolderKey
  /// A row that says why a folder could not be listed. It is not an item.
  let isStatus: Bool
  /// The item, or nil for a status row.
  var item: FileItem?
  /// What a status row says.
  var message: String?

  init(key: FolderKey, item: FileItem) {
    self.key = key
    self.item = item
    isStatus = false
  }

  init(statusFor key: FolderKey, message: String) {
    self.key = key
    self.message = message
    isStatus = true
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? OutlineNode else { return false }
    return other.key == key && other.isStatus == isStatus
  }

  override var hash: Int {
    var hasher = Hasher()
    hasher.combine(key)
    hasher.combine(isStatus)
    return hasher.finalize()
  }
}
