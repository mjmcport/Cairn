import CoreGraphics
import FileSystemCore
import Foundation

/// What makes a thumbnail valid: the file's place, the date it was last
/// changed and its size, and how large a picture was asked for. A file that
/// changes has a different key, so its old picture is never found.
struct ThumbnailKey: Hashable, Sendable {
  let path: String
  let modified: Date?
  let size: Int64?
  let pixelWidth: Int
  let pixelHeight: Int

  init(item: FileItem, pointSize: CGSize, scale: CGFloat) {
    path = item.url.path(percentEncoded: false)
    modified = item.modificationDate
    size = item.size
    pixelWidth = Int((pointSize.width * scale).rounded())
    pixelHeight = Int((pointSize.height * scale).rounded())
  }
}

/// Pictures that were made, bounded in how many and in how many bytes, least
/// recently used out first. A value type: whoever owns it serializes access.
struct ThumbnailCache {
  private struct Entry {
    let image: CGImage
    let cost: Int
    var tick: Int
  }

  let maxEntries: Int
  let maxBytes: Int
  private var entries: [ThumbnailKey: Entry] = [:]
  /// Touches in order, oldest first. A touch that was later superseded is
  /// stale and is skipped when it reaches the front.
  private var order: [(key: ThumbnailKey, tick: Int)] = []
  private var head = 0
  private var clock = 0
  private(set) var bytes = 0

  init(maxEntries: Int = 2_000, maxBytes: Int = 64 * 1_024 * 1_024) {
    self.maxEntries = maxEntries
    self.maxBytes = maxBytes
  }

  var count: Int { entries.count }

  /// The picture for `key`, which then counts as the most recently used.
  mutating func image(for key: ThumbnailKey) -> CGImage? {
    guard var entry = entries[key] else { return nil }
    clock += 1
    entry.tick = clock
    entries[key] = entry
    order.append((key, clock))
    return entry.image
  }

  /// Stores a picture, then drops the least recently used until both bounds
  /// hold. A picture larger than the byte bound is not kept at all.
  mutating func insert(_ image: CGImage, for key: ThumbnailKey) {
    let cost = image.bytesPerRow * image.height
    guard cost <= maxBytes else { return }
    if let old = entries[key] { bytes -= old.cost }
    clock += 1
    entries[key] = Entry(image: image, cost: cost, tick: clock)
    bytes += cost
    order.append((key, clock))
    evict()
  }

  private mutating func evict() {
    while entries.count > maxEntries || bytes > maxBytes, head < order.count {
      let touch = order[head]
      head += 1
      // Only the newest touch of a key counts.
      guard let entry = entries[touch.key], entry.tick == touch.tick else { continue }
      entries[touch.key] = nil
      bytes -= entry.cost
    }
    // The order list keeps stale touches until they reach the front, so it is
    // compacted when it has grown well past what is stored.
    if head > 1_024, head > order.count / 2 {
      order.removeFirst(head)
      head = 0
    }
  }
}
