import Foundation

/// Records each accessibility audit a UI test runs, and each retry after a
/// timeout. `scripts/accessibility-retries.py` counts the records after the
/// run.
///
/// Every record goes to the test process's log as one marked line, which
/// `xcodebuild` prints and `make uitest` collects. The UI test runner is
/// sandboxed and can only read the disk outside its container, so it cannot
/// write a file in the checkout. A process that is not sandboxed can also
/// name a file in the `CAIRN_AUDIT_LOG` environment variable and get the
/// same records there, one "event<TAB>screen" line each.
///
/// Every audit is recorded, not only the retries, because a run with no
/// retries would otherwise look the same as a recorder that never ran.
public struct AuditLog: Sendable {
  /// Starts every record in the test process's log.
  public static let marker = "CAIRN_AUDIT"

  /// The variable that names the optional file.
  public static let environmentVariable = "CAIRN_AUDIT_LOG"

  /// The file lines are also appended to, or `nil` for the log alone.
  public let url: URL?

  /// - Parameter environment: Read for ``environmentVariable``. Defaults to
  ///   the process's own environment.
  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    let path = environment[Self.environmentVariable] ?? ""
    url = path.isEmpty ? nil : URL(fileURLWithPath: path)
  }

  /// Records that an audit of `screen` is starting.
  public func recordAudit(screen: String) {
    append("audit", screen)
  }

  /// Records that the audit of `screen` timed out and is being run again.
  public func recordRetry(screen: String) {
    append("retry", screen)
  }

  /// The marked line for one record: the marker, an identifier, the event
  /// and the screen, separated by tabs. The identifier lets the counting
  /// script drop a line the log shows twice.
  public static func logLine(event: String, screen: String, identifier: UUID = UUID()) -> String {
    "\(marker)\t\(identifier.uuidString)\t\(event)\t\(screen)"
  }

  /// Writes the record to the log and, when a file is named, appends
  /// `event`, a tab, `screen` and a newline to it. A line that cannot be
  /// written is dropped: the counting script fails a run that recorded no
  /// audits, so a broken recorder does not pass unnoticed.
  private func append(_ event: String, _ screen: String) {
    NSLog("%@", Self.logLine(event: event, screen: screen))
    guard let url else { return }
    // O_APPEND, so lines from another instance or process are kept.
    let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard descriptor >= 0 else { return }
    defer { close(descriptor) }
    Data("\(event)\t\(screen)\n".utf8).withUnsafeBytes { bytes in
      _ = write(descriptor, bytes.baseAddress, bytes.count)
    }
  }
}
