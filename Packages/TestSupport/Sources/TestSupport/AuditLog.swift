import Foundation

/// Records each accessibility audit a UI test runs, and each retry after a
/// timeout, as one line in a file. `scripts/accessibility-retries.py` counts
/// the lines after the run.
///
/// The file is named by the `CAIRN_AUDIT_LOG` environment variable, which
/// `make uitest` sets. Without the variable nothing is recorded, so running
/// the tests from Xcode is unchanged.
///
/// Every audit is recorded, not only the retries, because a file with no
/// retries would otherwise look the same as a recorder that never ran.
public struct AuditLog: Sendable {
  /// The variable that names the file. `xcodebuild` passes a variable set as
  /// `TEST_RUNNER_CAIRN_AUDIT_LOG` to the test process under this name.
  public static let environmentVariable = "CAIRN_AUDIT_LOG"

  /// The file lines are appended to, or `nil` when nothing is recorded.
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

  /// Appends `event`, a tab, `screen` and a newline. A line that cannot be
  /// written is dropped: the counting script fails a run that recorded no
  /// audits, so a broken recorder does not pass unnoticed.
  private func append(_ event: String, _ screen: String) {
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
