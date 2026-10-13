import CoreGraphics
import FileMetadata
import Foundation

/// A provider that returns canned pictures, can hold each request at a gate,
/// and records what it was asked and how many ran at once.
final class StubThumbnailer: ThumbnailProviding, @unchecked Sendable {
  private let lock = NSLock()
  // Guarded by `lock`.
  private var requested: [URL] = []
  private var running = 0
  private var mostRunning = 0
  private var offMain = true
  private var fails: Set<URL> = []
  private var gates: [URL: Gate] = [:]

  /// A solid picture of `side` pixels, a few bytes a pixel.
  static func image(side: Int = 8) -> CGImage {
    let context = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
  }

  func hold(_ file: URL, at gate: Gate) { lock.withLock { gates[file] = gate } }
  func failFor(_ file: URL) { _ = lock.withLock { fails.insert(file) } }

  var requests: [URL] { lock.withLock { requested } }
  var mostAtOnce: Int { lock.withLock { mostRunning } }
  var neverOnTheMainThread: Bool { lock.withLock { offMain } }

  func thumbnail(for file: URL, pointSize: CGSize, scale: CGFloat) async -> CGImage? {
    let gate: Gate? = lock.withLock {
      requested.append(file)
      running += 1
      mostRunning = max(mostRunning, running)
      if Thread.isMainThread { offMain = false }
      return gates[file]
    }
    defer { lock.withLock { running -= 1 } }
    if let gate { await gate.pass() }
    if Task.isCancelled { return nil }
    return lock.withLock { fails.contains(file) } ? nil : Self.image()
  }
}
