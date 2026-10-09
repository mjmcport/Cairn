import Foundation

/// A uniquely named folder under the system temporary directory, for tests to
/// build fixtures in. Tests must never read or write real user folders.
///
/// Call ``remove()`` when the test ends, or use ``withTemporaryDirectory(_:)``,
/// which removes the folder for you.
public struct TemporaryDirectory: Sendable {
  /// The folder's location. The folder exists once `init` returns.
  public let url: URL

  /// Creates the folder.
  /// - Parameter prefix: Leads the folder name, to make leftovers easy to trace.
  public init(prefix: String = "CairnTests") throws {
    let base = FileManager.default.temporaryDirectory
    url = base.appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  /// Deletes the folder and everything in it.
  public func remove() throws {
    try FileManager.default.removeItem(at: url)
  }
}

/// Runs `body` with a fresh temporary folder and deletes the folder afterwards,
/// whether `body` returns or throws.
public func withTemporaryDirectory<Result>(
  prefix: String = "CairnTests",
  _ body: (URL) async throws -> Result
) async throws -> Result {
  let directory = try TemporaryDirectory(prefix: prefix)
  do {
    let result = try await body(directory.url)
    try directory.remove()
    return result
  } catch {
    try? directory.remove()
    throw error
  }
}
