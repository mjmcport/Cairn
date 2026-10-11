import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct MainThreadGuardTests {
  /// Collects violations from a handler.
  private final class Violations: @unchecked Sendable {
    // Guarded by `lock`.
    private var stored: [MainThreadGuard.Violation] = []
    private let lock = NSLock()

    var all: [MainThreadGuard.Violation] { lock.withLock { stored } }
    func record(_ violation: MainThreadGuard.Violation) {
      lock.withLock { stored.append(violation) }
    }
  }

  @Test @MainActor func firesOnTheMainThreadAndNamesTheEntryPoint() {
    let violations = Violations()
    MainThreadGuard.withHandler(violations.record) {
      MainThreadGuard.assertOffMainThread("sampleEntryPoint()")
    }
    #expect(violations.all.count == 1)
    #expect(violations.all.first?.entryPoint == "sampleEntryPoint()")
    #expect(violations.all.first?.file.hasSuffix("MainThreadGuardTests.swift") == true)
  }

  @Test func staysSilentOffTheMainThread() async {
    let violations = Violations()
    await MainThreadGuard.withHandler(violations.record) {
      await Task.detached {
        MainThreadGuard.assertOffMainThread()
      }.value
    }
    #expect(violations.all.isEmpty)
  }

  @Test @MainActor func listingAFolderOnTheMainThreadTripsTheGuard() throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }

    let violations = Violations()
    let items = try MainThreadGuard.withHandler(violations.record) {
      try DirectoryReader.readItems(in: tree.root)
    }
    #expect(items.count == 1)
    #expect(violations.all.map(\.entryPoint) == ["readItems(in:onCancellationCheck:onFirstItems:)"])
  }

  @Test @MainActor func listingThroughTheAsyncAPIFromTheMainActorDoesNotTripTheGuard() async throws
  {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }

    let violations = Violations()
    let items = try await MainThreadGuard.withHandler(violations.record) {
      try await DirectoryReader().items(in: tree.root)
    }
    #expect(items.count == 1)
    #expect(violations.all.isEmpty)
  }

  @Test @MainActor func consumingTheListingStreamOnTheMainActorDoesNotTripTheGuard() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }

    let violations = Violations()
    var counts: [Int] = []
    try await MainThreadGuard.withHandler(violations.record) {
      for try await event in DirectoryReader().listing(in: tree.root) {
        if case .allItems(let items) = event {
          counts.append(items.count)
        }
      }
    }
    #expect(counts == [1])
    #expect(violations.all.isEmpty)
  }

  @Test @MainActor func savingAndListingDiagnosticsOnTheMainThreadTripTheGuard() throws {
    let directory = try TemporaryDirectory()
    defer { try? directory.remove() }
    let store = LocalDiagnosticsStore(directory: directory.url)

    let violations = Violations()
    try MainThreadGuard.withHandler(violations.record) {
      try store.save(Data("{}".utf8), kind: "diagnostic")
      _ = try store.reports()
      store.saveAll([Data("{}".utf8)], kind: "diagnostic")
    }
    let entryPoints = Set(violations.all.map(\.entryPoint))
    #expect(entryPoints.contains("save(_:kind:date:)"))
    #expect(entryPoints.contains("saveAll(_:kind:)"))
    #expect(entryPoints.contains("reports()"))
  }

  @Test func handlersAreScopedToTheirTask() async {
    let first = Violations()
    let second = Violations()
    async let a: Void = MainThreadGuard.withHandler(first.record) {
      await MainActor.run { MainThreadGuard.assertOffMainThread("first") }
    }
    async let b: Void = MainThreadGuard.withHandler(second.record) {
      await MainActor.run { MainThreadGuard.assertOffMainThread("second") }
    }
    _ = await (a, b)
    #expect(first.all.map(\.entryPoint) == ["first"])
    #expect(second.all.map(\.entryPoint) == ["second"])
  }
}
