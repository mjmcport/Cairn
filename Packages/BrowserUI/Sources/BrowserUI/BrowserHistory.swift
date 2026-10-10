import Foundation

/// The back and forward history of one browser, with the selection that was
/// showing at each place, so returning somewhere restores what was selected.
public struct BrowserHistory: Sendable, Equatable {
  /// A place in the history and what was selected there.
  public struct Entry: Sendable, Equatable {
    public let location: URL
    public let selection: Set<URL>

    public init(location: URL, selection: Set<URL> = []) {
      self.location = location
      self.selection = selection
    }
  }

  /// The most back entries kept. Older ones are dropped.
  public static let limit = 100

  /// The folder being shown.
  public private(set) var current: URL
  /// Places to go back to, oldest first.
  public private(set) var backEntries: [Entry] = []
  /// Places to go forward to, nearest first.
  public private(set) var forwardEntries: [Entry] = []

  public init(current: URL) {
    self.current = current
  }

  public var canGoBack: Bool { !backEntries.isEmpty }
  public var canGoForward: Bool { !forwardEntries.isEmpty }

  /// Records a move to a new folder. Visiting the folder already showing
  /// changes nothing. Any forward history is discarded, as in a web browser.
  /// - Parameter selection: What is selected in the folder being left.
  public mutating func visit(_ location: URL, leaving selection: Set<URL> = []) {
    guard !Self.isSamePlace(location, current) else { return }
    backEntries.append(Entry(location: current, selection: selection))
    if backEntries.count > Self.limit {
      backEntries.removeFirst(backEntries.count - Self.limit)
    }
    forwardEntries.removeAll()
    current = location
  }

  /// Steps back one place.
  /// - Parameter selection: What is selected in the folder being left.
  /// - Returns: The place now showing and its remembered selection, or `nil`
  ///   when there is nowhere to go back to.
  public mutating func goBack(leaving selection: Set<URL> = []) -> Entry? {
    guard let entry = backEntries.popLast() else { return nil }
    forwardEntries.insert(Entry(location: current, selection: selection), at: 0)
    current = entry.location
    return entry
  }

  /// Steps forward one place. See ``goBack(leaving:)``.
  public mutating func goForward(leaving selection: Set<URL> = []) -> Entry? {
    guard !forwardEntries.isEmpty else { return nil }
    let entry = forwardEntries.removeFirst()
    backEntries.append(Entry(location: current, selection: selection))
    current = entry.location
    return entry
  }

  /// Whether two URLs name the same folder. See ``placeKey(_:)``.
  static func isSamePlace(_ lhs: URL, _ rhs: URL) -> Bool {
    placeKey(lhs) == placeKey(rhs)
  }

  /// A URL reduced to a comparable path: no trailing slash, and `.` and `..`
  /// resolved. A folder's URL may or may not end in a slash depending on
  /// where it came from.
  ///
  /// Only the path's text is read. Foundation's own standardizing is not
  /// used: it asks the disk whether the path exists, which is a file-system
  /// call on the main thread, and its answer has differed between macOS
  /// versions. Two spellings of one folder that differ by a symbolic link,
  /// such as `/tmp` and `/private/tmp`, are therefore different places.
  static func placeKey(_ url: URL) -> String {
    var components: [Substring] = []
    for component in url.path(percentEncoded: false).split(separator: "/") {
      switch component {
      case ".": continue
      // Above the root there is only the root.
      case "..": _ = components.popLast()
      default: components.append(component)
      }
    }
    return "/" + components.joined(separator: "/")
  }
}
