import Foundation
import Testing

@testable import TestSupport

/// Every test reads the file back as text, the way the script that counts the
/// lines does.
@Suite struct AuditLogTests {
  private func log(at url: URL) -> AuditLog {
    AuditLog(environment: [AuditLog.environmentVariable: url.path])
  }

  private func lines(of url: URL) throws -> [String] {
    try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  @Test func anAuditAppendsOneLineNamingTheScreen() async throws {
    try await withTemporaryDirectory { folder in
      let file = folder.appending(path: "audits.log")
      log(at: file).recordAudit(screen: "Sidebar")
      let text = try String(contentsOf: file, encoding: .utf8)
      #expect(text == "audit\tSidebar\n")
    }
  }

  @Test func aRetryAppendsALineAfterTheAuditLineForTheSameScreen() async throws {
    try await withTemporaryDirectory { folder in
      let file = folder.appending(path: "audits.log")
      let log = log(at: file)
      log.recordAudit(screen: "Sidebar")
      log.recordRetry(screen: "Sidebar")
      let written = try lines(of: file)
      #expect(written == ["audit\tSidebar", "retry\tSidebar"])
    }
  }

  @Test func withoutTheVariableNothingIsWritten() async throws {
    try await withTemporaryDirectory { folder in
      let log = AuditLog(environment: [:])
      log.recordAudit(screen: "Sidebar")
      log.recordRetry(screen: "Sidebar")
      #expect(log.url == nil)
      let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      #expect(names.isEmpty)
    }
  }

  @Test func anEmptyVariableRecordsNothing() {
    #expect(AuditLog(environment: [AuditLog.environmentVariable: ""]).url == nil)
  }

  @Test func aScreenNameWithSpacesIsReadBackWhole() async throws {
    try await withTemporaryDirectory { folder in
      let file = folder.appending(path: "audit log with spaces.log")
      log(at: file).recordAudit(screen: "Populated folder, list view")
      let written = try lines(of: file)
      let fields = try #require(written.first).split(separator: "\t")
      #expect(fields == ["audit", "Populated folder, list view"])
    }
  }

  @Test func appendsFromTwoInstancesBothSurvive() async throws {
    try await withTemporaryDirectory { folder in
      let file = folder.appending(path: "audits.log")
      log(at: file).recordAudit(screen: "First")
      log(at: file).recordAudit(screen: "Second")
      let written = try lines(of: file)
      #expect(written == ["audit\tFirst", "audit\tSecond"])
    }
  }

  /// The format `scripts/accessibility-retries.py extract` looks for.
  @Test func aLogLineIsTheMarkerAnIdentifierTheEventAndTheScreen() {
    let identifier = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let line = AuditLog.logLine(event: "retry", screen: "Empty folder", identifier: identifier)
    #expect(line == "CAIRN_AUDIT\t11111111-1111-4111-8111-111111111111\tretry\tEmpty folder")
  }

  @Test func twoLogLinesForTheSameRecordDifferOnlyInTheIdentifier() {
    let first = AuditLog.logLine(event: "audit", screen: "Sidebar")
    let second = AuditLog.logLine(event: "audit", screen: "Sidebar")
    #expect(first != second)
    #expect(first.split(separator: "\t").count == 4)
  }
}
