import Foundation

/// Keeps diagnostic reports (hangs, crashes, disk-write exceptions) as files
/// on this Mac. Nothing here sends a report anywhere; the user can open the
/// folder and choose to share a file.
public struct LocalDiagnosticsStore: Sendable {
  /// The folder that holds the reports.
  public let directory: URL
  /// How many reports are kept. Saving beyond this deletes the oldest.
  public let maximumReports: Int

  public init(directory: URL = LocalDiagnosticsStore.defaultDirectory, maximumReports: Int = 50) {
    self.directory = directory
    self.maximumReports = max(1, maximumReports)
  }

  /// `~/Library/Application Support/Cairn/Diagnostics`.
  public static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(
      path: "Cairn/Diagnostics", directoryHint: .isDirectory)
  }

  /// Writes one report and prunes the oldest beyond ``maximumReports``.
  /// - Parameters:
  ///   - report: The report's bytes, normally JSON.
  ///   - kind: A short label used in the file name, such as `"diagnostic"`.
  ///   - date: When the report was received. Names sort by this.
  /// - Returns: The file that was written.
  @discardableResult
  public func save(_ report: Data, kind: String, date: Date = .now) throws -> URL {
    MainThreadGuard.assertOffMainThread()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let stamp = date.formatted(
      .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(
        separator: .omitted)
    ).replacingOccurrences(of: ":", with: "-")
    let safeKind = kind.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    let suffix = UUID().uuidString.prefix(8)
    let file = directory.appending(
      path: "\(stamp)-\(safeKind.isEmpty ? "report" : safeKind)-\(suffix).json")

    try report.write(to: file, options: .atomic)
    try prune()
    return file
  }

  /// Writes each report, carrying on past one that cannot be saved.
  /// - Returns: How many reports were saved.
  @discardableResult
  public func saveAll(_ reports: [Data], kind: String) -> Int {
    MainThreadGuard.assertOffMainThread()
    var saved = 0
    for report in reports {
      do {
        try save(report, kind: kind)
        saved += 1
      } catch {
        Log.diagnostics.error("Could not save a diagnostic report: \(error.localizedDescription)")
      }
    }
    return saved
  }

  /// The saved reports, oldest first.
  public func reports() throws -> [URL] {
    MainThreadGuard.assertOffMainThread()
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default
      .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func prune() throws {
    let saved = try reports()
    for file in saved.dropLast(maximumReports) {
      try FileManager.default.removeItem(at: file)
    }
  }
}
