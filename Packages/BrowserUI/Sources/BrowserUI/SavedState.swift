import FileSystemCore
import Foundation

/// What Cairn remembers about its windows between launches: where each tab
/// was and how it was shown. A plain value with no AppKit in it, so it is
/// tested with values and written as one blob.
///
/// The window's frame and the list's column widths are not here: the system's
/// own autosave keeps them (see ``StateSaver``).
public struct SavedState: Codable, Equatable, Sendable {
  /// The shape of the data. A blob with any other version is ignored.
  public static let currentVersion = 1

  public var version: Int
  public var windows: [SavedWindow]

  public init(version: Int = SavedState.currentVersion, windows: [SavedWindow]) {
    self.version = version
    self.windows = windows
  }

  /// The state in `data`, or nil when it is damaged or from another version.
  public static func decode(_ data: Data) -> SavedState? {
    guard let state = try? JSONDecoder().decode(SavedState.self, from: data),
      state.version == currentVersion
    else { return nil }
    return state
  }

  public func encoded() -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(self)
  }
}

public struct SavedWindow: Codable, Equatable, Sendable {
  public var sidebarWidth: Double?
  public var sidebarCollapsed: Bool
  public var showsPathBar: Bool
  public var tabs: [SavedTab]
  public var showingIndex: Int

  public init(
    sidebarWidth: Double? = nil, sidebarCollapsed: Bool = false, showsPathBar: Bool = true,
    tabs: [SavedTab], showingIndex: Int = 0
  ) {
    self.sidebarWidth = sidebarWidth
    self.sidebarCollapsed = sidebarCollapsed
    self.showsPathBar = showsPathBar
    self.tabs = tabs
    self.showingIndex = showingIndex
  }

  /// `showingIndex` clamped to the tabs that exist, so a damaged value never
  /// points past the end. Zero when there are no tabs.
  public var validShowingIndex: Int {
    tabs.isEmpty ? 0 : min(max(showingIndex, 0), tabs.count - 1)
  }
}

public struct SavedTab: Codable, Equatable, Sendable {
  /// A folder's file URL, or a virtual location's URL, as a string.
  public var location: String
  public var viewMode: SavedViewMode
  public var sort: SavedSort
  public var showsHidden: Bool
  public var openFolders: [[String]]
  public var selection: [String]
  public var back: [SavedHistoryEntry]
  public var forward: [SavedHistoryEntry]

  /// The most entries kept in each direction (R9).
  public static let historyLimit = 20

  public init(
    location: String, viewMode: SavedViewMode = .list, sort: SavedSort = SavedSort(),
    showsHidden: Bool = false, openFolders: [[String]] = [], selection: [String] = [],
    back: [SavedHistoryEntry] = [], forward: [SavedHistoryEntry] = []
  ) {
    self.location = location
    self.viewMode = viewMode
    self.sort = sort
    self.showsHidden = showsHidden
    self.openFolders = openFolders
    self.selection = selection
    // The nearest entries are the ones worth keeping.
    self.back = Array(back.suffix(Self.historyLimit))
    self.forward = Array(forward.prefix(Self.historyLimit))
  }
}

public struct SavedHistoryEntry: Codable, Equatable, Sendable {
  public var location: String
  public var selection: [String]
  public var openFolders: [[String]]

  public init(location: String, selection: [String] = [], openFolders: [[String]] = []) {
    self.location = location
    self.selection = selection
    self.openFolders = openFolders
  }
}

public enum SavedViewMode: String, Codable, Equatable, Sendable {
  case list, icons, columns
}

public struct SavedSort: Codable, Equatable, Sendable {
  public enum Key: String, Codable, Equatable, Sendable {
    case name, size, sizeOnDisk, modificationDate, dateAdded
  }

  public var key: Key
  public var ascending: Bool
  public var foldersFirst: Bool

  public init(key: Key = .name, ascending: Bool = true, foldersFirst: Bool = false) {
    self.key = key
    self.ascending = ascending
    self.foldersFirst = foldersFirst
  }
}

// MARK: - Conversion to and from the live types

extension SavedViewMode {
  init(_ mode: BrowserModel.ViewMode) {
    switch mode {
    case .list: self = .list
    case .icons: self = .icons
    case .columns: self = .columns
    }
  }

  var browserMode: BrowserModel.ViewMode {
    switch self {
    case .list: .list
    case .icons: .icons
    case .columns: .columns
    }
  }
}

extension SavedSort {
  public init(_ sort: FileItemSort) {
    let key: Key
    switch sort.key {
    case .name: key = .name
    case .size: key = .size
    case .sizeOnDisk: key = .sizeOnDisk
    case .modificationDate: key = .modificationDate
    case .dateAdded: key = .dateAdded
    }
    self.init(key: key, ascending: sort.ascending, foldersFirst: sort.foldersFirst)
  }

  public var fileItemSort: FileItemSort {
    let live: FileItemSort.Key
    switch key {
    case .name: live = .name
    case .size: live = .size
    case .sizeOnDisk: live = .sizeOnDisk
    case .modificationDate: live = .modificationDate
    case .dateAdded: live = .dateAdded
    }
    return FileItemSort(key: live, ascending: ascending, foldersFirst: foldersFirst)
  }
}

// MARK: - Storage

/// Where the saved blob lives. A protocol so tests use memory.
public protocol StateStoring: AnyObject {
  func load() -> Data?
  func save(_ data: Data)
  func clear()
}

/// The user defaults hold the blob: no file is touched, so saving is safe on
/// the main thread (R12), and the system already caches it.
public final class UserDefaultsStateStore: StateStoring {
  public static let key = "SavedWindowState"
  /// The launch argument that names a suite, so end-to-end tests never read
  /// or write the app's real state.
  public static let suiteArgument = "StateSuite"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  /// The store the app uses: the suite named by `-StateSuite` when given,
  /// otherwise the standard defaults.
  public static func forLaunch(defaults: UserDefaults = .standard) -> UserDefaultsStateStore {
    if let name = defaults.string(forKey: suiteArgument), !name.isEmpty,
      let suite = UserDefaults(suiteName: name)
    {
      return UserDefaultsStateStore(defaults: suite)
    }
    return UserDefaultsStateStore(defaults: defaults)
  }

  public func load() -> Data? { defaults.data(forKey: Self.key) }
  public func save(_ data: Data) { defaults.set(data, forKey: Self.key) }
  public func clear() { defaults.removeObject(forKey: Self.key) }
}
