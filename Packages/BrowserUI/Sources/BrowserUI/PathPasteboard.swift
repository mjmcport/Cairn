import AppKit

/// Where Copy Path puts what it copies. The protocol exists so tests do not
/// touch the system pasteboard, which is a service another process answers.
@MainActor
public protocol PathPasteboard {
  /// Replaces the contents with `text`, and with `urls` as file URLs when
  /// there are any.
  func replace(with text: String, urls: [URL])
}

/// The general pasteboard.
@MainActor
public struct SystemPathPasteboard: PathPasteboard {
  public init() {}

  public func replace(with text: String, urls: [URL]) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    if !urls.isEmpty {
      pasteboard.writeObjects(urls as [NSURL])
    }
  }
}
