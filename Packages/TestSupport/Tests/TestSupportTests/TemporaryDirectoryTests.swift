import Foundation
import Testing

@testable import TestSupport

@Suite struct TemporaryDirectoryTests {
  @Test func createsAnEmptyFolderUnderTheSystemTemporaryDirectory() throws {
    let directory = try TemporaryDirectory()
    defer { try? directory.remove() }

    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: directory.url.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)

    let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
    #expect(directory.url.resolvingSymlinksInPath().path.hasPrefix(temporaryRoot))
  }

  @Test func removesTheFolderWhenTheBodyReturns() async throws {
    let url = try await withTemporaryDirectory { url in
      try Data("x".utf8).write(to: url.appending(path: "file.txt"))
      return url
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func removesTheFolderWhenTheBodyThrows() async throws {
    struct Failure: Error {}
    let recorder = URLRecorder()
    await #expect(throws: Failure.self) {
      try await withTemporaryDirectory { url in
        await recorder.record(url)
        throw Failure()
      }
    }
    let url = try #require(await recorder.url)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }
}

private actor URLRecorder {
  var url: URL?
  func record(_ url: URL) { self.url = url }
}
