import CoreGraphics
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The loader and the cache behind the icon view's pictures
/// (plans/phase-1a-step-06-icon-view.md, U3). No test waits on a clock: each
/// waits on a gate or on a request's own completion.
@Suite struct ThumbnailLoaderTests {
  private let size = CGSize(width: 64, height: 64)

  private func item(
    _ name: String, size: Int64 = 100, modified: TimeInterval = 1_000, onlineOnly: Bool = false
  ) -> FileItem {
    FileItem(
      url: URL(filePath: "/fixture/\(name)"), kind: .file, size: size,
      modificationDate: Date(timeIntervalSince1970: modified), isOnlineOnly: onlineOnly)
  }

  // MARK: The loader

  @Test func aPictureIsMadeOnceAndThenComesFromTheCache() async {
    let provider = StubThumbnailer()
    let loader = ThumbnailLoader(provider: provider)
    let photo = item("a.png")

    #expect(await loader.picture(for: photo, pointSize: size, scale: 2) != nil)
    #expect(await loader.picture(for: photo, pointSize: size, scale: 2) != nil)
    #expect(provider.requests.count == 1)
  }

  @Test func aFileThatChangedOrAnotherSizeIsADifferentPicture() async {
    let provider = StubThumbnailer()
    let loader = ThumbnailLoader(provider: provider)

    _ = await loader.picture(for: item("a.png"), pointSize: size, scale: 2)
    _ = await loader.picture(for: item("a.png", modified: 2_000), pointSize: size, scale: 2)
    _ = await loader.picture(for: item("a.png", size: 101), pointSize: size, scale: 2)
    _ = await loader.picture(
      for: item("a.png"), pointSize: CGSize(width: 128, height: 128), scale: 2)
    #expect(provider.requests.count == 4)
  }

  @Test func anOnlineOnlyItemIsNeverGivenToTheProvider() async {
    let provider = StubThumbnailer()
    let loader = ThumbnailLoader(provider: provider)

    #expect(
      await loader.picture(for: item("cloud.png", onlineOnly: true), pointSize: size, scale: 2)
        == nil)
    #expect(provider.requests.isEmpty)
    #expect(await loader.cached.count == 0)
  }

  @Test func aProviderThatHasNoPictureLeavesNothingCached() async {
    let provider = StubThumbnailer()
    let broken = item("broken.bin")
    provider.failFor(broken.url)
    let loader = ThumbnailLoader(provider: provider)

    #expect(await loader.picture(for: broken, pointSize: size, scale: 2) == nil)
    #expect(await loader.cached.count == 0)
  }

  @Test func atMostTheLimitRunAtOnce() async {
    let provider = StubThumbnailer()
    let gate = Gate()
    let items = (0..<10).map { item("f\($0).png") }
    for file in items { provider.hold(file.url, at: gate) }
    let loader = ThumbnailLoader(provider: provider, maxInFlight: 3)

    let tasks = items.map { file in
      Task { await loader.picture(for: file, pointSize: size, scale: 2) }
    }
    await gate.waitUntilReached()
    await gate.open()
    for task in tasks { _ = await task.value }
    #expect(provider.requests.count == 10)
    #expect(provider.mostAtOnce <= 3)
    #expect(provider.mostAtOnce >= 1)
  }

  @Test func theRequestAskedForLastIsServedFirst() async {
    let provider = StubThumbnailer()
    let first = Gate()
    let items = (0..<4).map { item("f\($0).png") }
    provider.hold(items[0].url, at: first)
    let loader = ThumbnailLoader(provider: provider, maxInFlight: 1)

    // The first takes the only slot and waits at its gate.
    let running = Task { await loader.picture(for: items[0], pointSize: size, scale: 2) }
    await first.waitUntilReached()
    // Three more queue up, in order.
    var queued: [Task<CGImage?, Never>] = []
    for file in items.dropFirst() {
      queued.append(Task { await loader.picture(for: file, pointSize: size, scale: 2) })
      // Let each one reach the queue before the next is asked for.
      while await loader.waitingCount < queued.count { await Task.yield() }
    }

    await first.open()
    _ = await running.value
    for task in queued { _ = await task.value }
    #expect(provider.requests.map(\.lastPathComponent) == ["f0.png", "f3.png", "f2.png", "f1.png"])
  }

  @Test func aRequestCancelledWhileItWaitsIsNeverMade() async {
    let provider = StubThumbnailer()
    let first = Gate()
    let items = (0..<2).map { item("f\($0).png") }
    provider.hold(items[0].url, at: first)
    let loader = ThumbnailLoader(provider: provider, maxInFlight: 1)

    let running = Task { await loader.picture(for: items[0], pointSize: size, scale: 2) }
    await first.waitUntilReached()
    let waiting = Task { await loader.picture(for: items[1], pointSize: size, scale: 2) }
    while await loader.waitingCount < 1 { await Task.yield() }

    waiting.cancel()
    #expect(await waiting.value == nil)
    await first.open()
    _ = await running.value
    #expect(provider.requests.map(\.lastPathComponent) == ["f0.png"])
  }

  @Test func theProviderIsNeverCalledOnTheMainThread() async {
    let provider = StubThumbnailer()
    let loader = ThumbnailLoader(provider: provider)
    await MainActor.run {
      Task { _ = await loader.picture(for: item("a.png"), pointSize: size, scale: 2) }
    }.value
    #expect(provider.neverOnTheMainThread)
    #expect(provider.requests.count == 1)
  }

  // MARK: The cache

  private func key(_ index: Int) -> ThumbnailKey {
    ThumbnailKey(item: item("f\(index).png"), pointSize: size, scale: 2)
  }

  @Test func theCacheStaysInsideItsBoundsWhenAHundredThousandPicturesPassThrough() {
    var cache = ThumbnailCache(maxEntries: 500, maxBytes: 1_000_000)
    let image = StubThumbnailer.image(side: 16)
    for index in 0..<100_000 {
      cache.insert(image, for: key(index))
      #expect(cache.count <= 500)
      #expect(cache.bytes <= 1_000_000)
    }
    #expect(cache.count == 500)
  }

  @Test func theLeastRecentlyUsedGoesFirstAndALookupCountsAsUse() {
    var cache = ThumbnailCache(maxEntries: 3, maxBytes: 1_000_000)
    let image = StubThumbnailer.image()
    for index in 0..<3 { cache.insert(image, for: key(index)) }
    // Touch the oldest, then add one more.
    #expect(cache.image(for: key(0)) != nil)
    cache.insert(image, for: key(3))

    #expect(cache.image(for: key(1)) == nil)
    #expect(cache.image(for: key(0)) != nil)
    #expect(cache.image(for: key(2)) != nil)
    #expect(cache.image(for: key(3)) != nil)
  }

  @Test func theByteBoundEvictsAndAPictureLargerThanItIsNotKept() {
    let small = StubThumbnailer.image(side: 16)  // 1 KB
    let big = StubThumbnailer.image(side: 64)  // 16 KB
    var cache = ThumbnailCache(maxEntries: 100, maxBytes: 3_000)
    for index in 0..<10 { cache.insert(small, for: key(index)) }
    #expect(cache.bytes <= 3_000)
    #expect(cache.count == 2)

    cache.insert(big, for: key(99))
    #expect(cache.image(for: key(99)) == nil)
  }

  @Test func insertingTheSameKeyAgainReplacesItWithoutDoubleCounting() {
    var cache = ThumbnailCache(maxEntries: 10, maxBytes: 1_000_000)
    let image = StubThumbnailer.image()
    cache.insert(image, for: key(1))
    let bytes = cache.bytes
    cache.insert(image, for: key(1))
    #expect(cache.count == 1)
    #expect(cache.bytes == bytes)
  }
}
