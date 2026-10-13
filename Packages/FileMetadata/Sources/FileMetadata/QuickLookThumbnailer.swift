import CoreGraphics
import FileSystemCore
import Foundation
import QuickLookThumbnailing

/// Thumbnails from the system's Quick Look generator, made on this Mac.
public struct QuickLookThumbnailer: ThumbnailProviding {
  public init() {}

  public func thumbnail(for file: URL, pointSize: CGSize, scale: CGFloat) async -> CGImage? {
    MainThreadGuard.assertOffMainThread()
    let request = RequestBox(
      QLThumbnailGenerator.Request(
        fileAt: file, size: pointSize, scale: scale, representationTypes: .all))
    return await withTaskCancellationHandler {
      guard !Task.isCancelled else { return nil }
      // A file that cannot be drawn is an error the caller answers with its
      // own icon, so the reason is not needed.
      let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
        for: request.value)
      return Task.isCancelled ? nil : representation?.cgImage
    } onCancel: {
      QLThumbnailGenerator.shared.cancel(request.value)
    }
  }
}

/// Carries a request into the cancellation handler. The generator's request
/// is not marked sendable; it is made once and only read afterwards.
private final class RequestBox: @unchecked Sendable {
  let value: QLThumbnailGenerator.Request

  init(_ value: QLThumbnailGenerator.Request) {
    self.value = value
  }
}
