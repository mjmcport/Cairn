import Foundation

/// What has been typed to select an item by its name: letters typed close
/// together make one prefix, and a pause starts a new one. A value with no
/// clock of its own, so it is tested without a window or a wait.
struct TypeAhead: Equatable {
  /// How long a pause ends what was typed.
  static let timeout: TimeInterval = 1.0

  private(set) var prefix = ""
  private var lastTyped: TimeInterval?

  /// Adds `text`, typed at `time` (an event's timestamp, in seconds), and
  /// returns the prefix to select by.
  mutating func type(_ text: String, at time: TimeInterval) -> String {
    if let lastTyped, time - lastTyped > Self.timeout {
      prefix = ""
    }
    prefix += text
    lastTyped = time
    return prefix
  }

  /// The index of the first name that starts with `prefix`, ignoring case
  /// and diacritics as Finder does.
  static func match(_ prefix: String, in names: [String]) -> Int? {
    guard !prefix.isEmpty else { return nil }
    return names.firstIndex {
      $0.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}
