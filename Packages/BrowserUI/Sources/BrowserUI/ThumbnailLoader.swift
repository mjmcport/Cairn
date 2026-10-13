import CoreGraphics
import FileMetadata
import FileSystemCore
import Foundation

/// Makes the pictures of the items a view shows, off the main actor, for the
/// ones that are wanted and in the order they are wanted.
///
/// A view asks for a picture when a cell is about to be shown and cancels the
/// task that asked when the cell goes away. The loader answers from its cache,
/// or from the provider with at most `maxInFlight` requests running; when
/// more are waiting, the one asked for last goes first, because it is the one
/// nearest the screen.
///
/// An online-only item is never given to the provider: drawing a file can
/// make the system download it.
actor ThumbnailLoader {
  private let provider: any ThumbnailProviding
  private let maxInFlight: Int
  private var cache: ThumbnailCache
  private var inFlight = 0
  private var nextWaiter = 0
  private var waiters: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []

  /// Called for every request that reached the provider, for tests.
  private(set) var providerRequests = 0

  init(provider: any ThumbnailProviding, maxInFlight: Int = 4, cache: ThumbnailCache = .init()) {
    self.provider = provider
    self.maxInFlight = max(1, maxInFlight)
    self.cache = cache
  }

  /// How many requests are waiting for a slot, for tests.
  var waitingCount: Int { waiters.count }

  /// How many pictures are cached and how many bytes they take.
  var cached: (count: Int, bytes: Int) { (cache.count, cache.bytes) }

  /// The picture of `item`, or nil when there is none to show: the item is
  /// online only, the provider has none, or the request was cancelled.
  func picture(for item: FileItem, pointSize: CGSize, scale: CGFloat) async -> CGImage? {
    guard !item.isOnlineOnly else { return nil }
    let key = ThumbnailKey(item: item, pointSize: pointSize, scale: scale)
    if let image = cache.image(for: key) { return image }
    guard await acquire() else { return nil }
    defer { release() }
    // Another request may have made it while this one waited.
    if let image = cache.image(for: key) { return image }
    providerRequests += 1
    let image = await provider.thumbnail(for: item.url, pointSize: pointSize, scale: scale)
    guard let image, !Task.isCancelled else { return nil }
    cache.insert(image, for: key)
    return image
  }

  // MARK: Slots

  /// Takes a slot, waiting for one if all are taken. The waiter asked for
  /// last is served first.
  /// - Returns: false when the request was cancelled while it waited.
  private func acquire() async -> Bool {
    if Task.isCancelled { return false }
    if inFlight < maxInFlight {
      inFlight += 1
      return true
    }
    nextWaiter += 1
    let id = nextWaiter
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        waiters.append((id, continuation))
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  private func cancelWaiter(_ id: Int) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    let waiter = waiters.remove(at: index)
    waiter.continuation.resume(returning: false)
  }

  private func release() {
    if let waiter = waiters.popLast() {
      // The slot passes straight to the newest waiter.
      waiter.continuation.resume(returning: true)
    } else {
      inFlight -= 1
    }
  }
}
