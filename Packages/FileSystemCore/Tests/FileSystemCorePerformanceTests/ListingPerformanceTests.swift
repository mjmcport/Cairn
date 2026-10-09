import FileSystemCore
import TestSupport
import XCTest

/// Performance baselines for listing large folders (quality bar 4).
///
/// Run with `make perf`, which builds in release mode, parses the measured
/// averages and compares them with `docs/performance/baseline.json`.
final class ListingPerformanceTests: XCTestCase {
  /// Built once for the whole class: creating 100,000 files takes seconds.
  private static let tree: FixtureTree = {
    do {
      return try FixtureTree.build {
        FixtureNode.files(count: 10_000, in: "Items10000")
        FixtureNode.files(count: 100_000, in: "Items100000")
      }
    } catch {
      fatalError("Could not build the performance fixture: \(error)")
    }
  }()

  /// Metadata a Get Info panel reads beyond what a listing prefetches.
  private static let detailKeys: Set<URLResourceKey> = [
    .creationDateKey, .addedToDirectoryDateKey, .totalFileAllocatedSizeKey, .tagNamesKey,
    .contentTypeKey,
  ]

  override class func tearDown() {
    try? tree.remove()
    super.tearDown()
  }

  private var options: XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    return options
  }

  /// Runs `work` off the main thread and waits for it, as the app does.
  private func runOffMain<Result: Sendable>(_ work: @escaping @Sendable () async throws -> Result)
    -> Result
  {
    let finished = expectation(description: "work finished")
    let box = ResultBox<Result>()
    Task.detached {
      do {
        box.result = .success(try await work())
      } catch {
        box.result = .failure(error)
      }
      finished.fulfill()
    }
    wait(for: [finished], timeout: 300)
    do {
      return try XCTUnwrap(box.result).get()
    } catch {
      fatalError("Performance work failed: \(error)")
    }
  }

  private func measureListing(_ folder: String, expecting count: Int) {
    let url = Self.tree.url(folder)
    measure(metrics: [XCTClockMetric()], options: options) {
      let items = runOffMain { try await DirectoryReader().items(in: url) }
      XCTAssertEqual(items.count, count)
    }
  }

  private func measureDetailMetadata(_ folder: String, expecting count: Int) {
    let url = Self.tree.url(folder)
    let keys = Self.detailKeys
    let paths = runOffMain { try await DirectoryReader().items(in: url) }.map(\.url.path)
    XCTAssertEqual(paths.count, count)

    measure(metrics: [XCTClockMetric()], options: options) {
      let read = runOffMain {
        var read = 0
        for path in paths {
          // A fresh URL each time, so nothing is served from a URL's cache.
          _ = try URL(filePath: path).resourceValues(forKeys: keys)
          read += 1
        }
        return read
      }
      XCTAssertEqual(read, count)
    }
  }

  private func measureSorting(_ folder: String, by sort: FileItemSort) {
    let url = Self.tree.url(folder)
    let items = runOffMain { try await DirectoryReader().items(in: url) }.shuffled()
    measure(metrics: [XCTClockMetric()], options: options) {
      XCTAssertEqual(sort.sorted(items).count, items.count)
    }
  }

  func testList10000() { measureListing("Items10000", expecting: 10_000) }
  func testList100000() { measureListing("Items100000", expecting: 100_000) }

  func testDetailMetadata10000() { measureDetailMetadata("Items10000", expecting: 10_000) }
  func testDetailMetadata100000() { measureDetailMetadata("Items100000", expecting: 100_000) }

  func testSortByName10000() { measureSorting("Items10000", by: FileItemSort()) }
  func testSortByName100000() { measureSorting("Items100000", by: FileItemSort()) }
}

private final class ResultBox<Value: Sendable>: @unchecked Sendable {
  // Written once by the detached task before the expectation is fulfilled,
  // and read only after the wait returns.
  var result: Result<Value, any Error>?
}
