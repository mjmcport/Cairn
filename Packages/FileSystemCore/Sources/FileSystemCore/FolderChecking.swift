import Foundation

/// Answers whether a place can still be shown as a folder.
public protocol FolderChecking: Sendable {
  /// Whether `url` names a folder that exists and can be listed. Touches the
  /// file system; never call it on the main thread.
  func isListableFolder(_ url: URL) -> Bool
}

/// Asks the file system.
public struct DiskFolderChecker: FolderChecking {
  public init() {}

  public func isListableFolder(_ url: URL) -> Bool {
    MainThreadGuard.assertOffMainThread()
    var isDirectory: ObjCBool = false
    let path = url.path(percentEncoded: false)
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && isDirectory.boolValue && FileManager.default.isReadableFile(atPath: path)
  }
}
