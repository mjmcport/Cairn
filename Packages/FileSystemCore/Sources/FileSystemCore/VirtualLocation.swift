import Foundation

/// A place that is not a folder: the files that carry a tag, or the files used
/// lately. It is a URL like any other location, with a scheme of its own, so
/// that history, tabs and the title need no new idea. A reader answers a
/// listing of one with a query.
public enum VirtualLocation: Sendable, Equatable {
  /// Files that carry the tag called this.
  case tag(String)
  /// Files used in the last days, most recent first.
  case recents

  public static let tagScheme = "cairn-tag"
  public static let recentsScheme = "cairn-recents"

  /// The URL that stands for this place. A tag's name is percent-encoded, so
  /// any name round-trips, and the URL's last path component is the name,
  /// which titles the tab.
  public var url: URL {
    switch self {
    case .tag(let name):
      var components = URLComponents()
      components.scheme = Self.tagScheme
      components.path = "/" + name
      return components.url ?? URL(string: "\(Self.tagScheme):///")!
    case .recents:
      var components = URLComponents()
      components.scheme = Self.recentsScheme
      components.path = "/Recents"
      return components.url ?? URL(string: "\(Self.recentsScheme):///Recents")!
    }
  }

  /// The place a URL stands for, or nil for a URL that is not virtual.
  public init?(url: URL) {
    switch url.scheme {
    case Self.tagScheme:
      let name = String(url.path(percentEncoded: false).dropFirst())
      guard !name.isEmpty else { return nil }
      self = .tag(name)
    case Self.recentsScheme:
      self = .recents
    default:
      return nil
    }
  }

  /// Whether `url` is a virtual location.
  public static func isVirtual(_ url: URL) -> Bool {
    url.scheme == tagScheme || url.scheme == recentsScheme
  }

  /// What the tab is called.
  public var title: String {
    switch self {
    case .tag(let name): name
    case .recents: "Recents"
    }
  }
}
