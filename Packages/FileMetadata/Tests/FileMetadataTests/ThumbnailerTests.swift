import CoreGraphics
import FileSystemCore
import Foundation
import ImageIO
import TestSupport
import Testing
import UniformTypeIdentifiers

@testable import FileMetadata

/// The real Quick Look provider against files the test makes. Asks only that
/// a picture comes back and that cancellation and the guard are honoured: how
/// a picture looks is the system's.
@Suite struct ThumbnailerTests {
  private func writePNG(_ url: URL, side: Int = 256) throws {
    var pixels = [UInt8](repeating: 200, count: side * side * 4)
    for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
    let context = try #require(
      CGContext(
        data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
  }

  @Test func anImageFileGetsAPictureNoLargerThanAskedFor() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("notes.txt") }
    defer { try? tree.remove() }
    let url = tree.url("photo.png")
    try writePNG(url)

    let picture = await QuickLookThumbnailer().thumbnail(
      for: url, pointSize: CGSize(width: 64, height: 64), scale: 2)
    let image = try #require(picture)
    #expect(image.width > 0 && image.width <= 128)
    #expect(image.height > 0 && image.height <= 128)
  }

  @Test func aCancelledRequestReturnsNothing() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }
    let url = tree.url("photo.png")
    try writePNG(url)

    let picture = await Task {
      // Cancelled before the request is made, deterministically.
      withUnsafeCurrentTask { $0?.cancel() }
      return await QuickLookThumbnailer().thumbnail(
        for: url, pointSize: CGSize(width: 64, height: 64), scale: 2)
    }.value
    #expect(picture == nil)
  }

  @Test func askingFromTheMainActorRunsTheRequestOffTheMainThread() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }
    let url = tree.url("photo.png")
    try writePNG(url)

    // Asked from the main actor, the call hops off it, so the guard has
    // nothing to report.
    let violations = Recorded()
    let picture = await MainActor.run {
      Task {
        await MainThreadGuard.withHandler({ violations.add($0) }) {
          await QuickLookThumbnailer().thumbnail(
            for: url, pointSize: CGSize(width: 64, height: 64), scale: 2)
        }
      }
    }.value
    #expect(picture != nil)
    #expect(violations.count == 0)
  }

  /// Violations from any thread.
  private final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [MainThreadGuard.Violation] = []
    var count: Int { lock.withLock { all.count } }
    func add(_ violation: MainThreadGuard.Violation) { lock.withLock { all.append(violation) } }
  }
}
