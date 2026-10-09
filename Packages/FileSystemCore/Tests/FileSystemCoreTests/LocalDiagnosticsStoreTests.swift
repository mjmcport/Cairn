import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct LocalDiagnosticsStoreTests {
  @Test func savesAReportAsAFileInItsFolder() async throws {
    try await withTemporaryDirectory { root in
      let folder = root.appending(path: "Cairn/Diagnostics", directoryHint: .isDirectory)
      let store = LocalDiagnosticsStore(directory: folder)
      #expect(try store.reports().isEmpty)

      let report = Data(#"{"hangDiagnostics":[]}"#.utf8)
      let file = try store.save(
        report, kind: "diagnostic", date: Date(timeIntervalSince1970: 1_700_000_000))

      #expect(file.deletingLastPathComponent().path == folder.path)
      #expect(file.lastPathComponent.hasPrefix("2023-11-14T22-13-20"))
      #expect(file.lastPathComponent.contains("-diagnostic-"))
      #expect(file.pathExtension == "json")
      #expect(try Data(contentsOf: file) == report)
      #expect(try store.reports().map(\.lastPathComponent) == [file.lastPathComponent])
    }
  }

  @Test func keepsOnlyTheNewestReports() async throws {
    try await withTemporaryDirectory { root in
      let store = LocalDiagnosticsStore(directory: root, maximumReports: 3)
      for index in 0..<5 {
        try store.save(
          Data("\(index)".utf8), kind: "diagnostic",
          date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60))
      }

      let kept = try store.reports()
      #expect(kept.count == 3)
      #expect(
        try kept.map { try String(decoding: Data(contentsOf: $0), as: UTF8.self) } == [
          "2", "3", "4",
        ])
    }
  }

  @Test func reportsSavedInTheSameInstantDoNotOverwriteEachOther() async throws {
    try await withTemporaryDirectory { root in
      let store = LocalDiagnosticsStore(directory: root)
      let date = Date(timeIntervalSince1970: 1_700_000_000)
      let first = try store.save(Data("a".utf8), kind: "diagnostic", date: date)
      let second = try store.save(Data("b".utf8), kind: "diagnostic", date: date)
      #expect(first != second)
      #expect(try store.reports().count == 2)
    }
  }

  @Test func savingSeveralReportsCountsOnlyTheOnesThatWereSaved() async throws {
    try await withTemporaryDirectory { root in
      let reports = [Data("a".utf8), Data("b".utf8)]
      let store = LocalDiagnosticsStore(directory: root.appending(path: "Diagnostics"))
      #expect(store.saveAll(reports, kind: "diagnostic") == 2)
      #expect(try store.reports().count == 2)

      // A folder cannot be created inside a file, so every save here fails.
      let file = root.appending(path: "file.txt")
      try Data().write(to: file)
      let blocked = LocalDiagnosticsStore(directory: file.appending(path: "Diagnostics"))
      #expect(blocked.saveAll(reports, kind: "diagnostic") == 0)
    }
  }

  @Test func aKindCannotEscapeTheFolder() async throws {
    try await withTemporaryDirectory { root in
      let folder = root.appending(path: "Diagnostics", directoryHint: .isDirectory)
      let store = LocalDiagnosticsStore(directory: folder)
      let file = try store.save(Data("x".utf8), kind: "../../evil/kind")
      #expect(file.deletingLastPathComponent().path == folder.path)
      #expect(!file.lastPathComponent.contains("/"))
      #expect(file.lastPathComponent.contains("-evilkind-"))
    }
  }

  @Test func theDefaultFolderIsUnderApplicationSupport() {
    let path = LocalDiagnosticsStore.defaultDirectory.path
    #expect(path.hasSuffix("/Library/Application Support/Cairn/Diagnostics"))
  }

  @Test func logCategoriesShareOneSubsystem() {
    #expect(Log.subsystem == "com.mjmcport.cairn")
    #expect(
      Log.categories == ["filesystem", "metadata", "operations", "ui", "lifecycle", "diagnostics"])
  }
}
