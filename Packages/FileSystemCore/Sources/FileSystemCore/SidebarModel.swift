import Foundation

/// One row of the sidebar.
public struct SidebarItem: Sendable, Equatable, Identifiable {
  public enum Kind: Sendable, Equatable {
    case recents
    case favorite
    case volume
    case cloud
    case tag
  }

  /// Stable across rebuilds, so a selection survives a refresh of the list.
  public let id: String
  public let title: String
  /// A folder URL for a folder, a volume or a cloud folder, and a virtual
  /// URL (``VirtualLocation``) for a tag or the recents.
  public let location: URL
  public let kind: Kind
  /// An SF Symbol name for the row's icon.
  public let symbolName: String
  /// Whether the volume can be ejected, and the row has an eject button.
  public var canEject = false
  /// Whether the person can remove the row from the sidebar.
  public var canRemove = false
  /// Whether the folder the row stands for could not be found.
  public var isMissing = false

  public init(
    id: String, title: String, location: URL, kind: Kind, symbolName: String,
    canEject: Bool = false, canRemove: Bool = false, isMissing: Bool = false
  ) {
    self.id = id
    self.title = title
    self.location = location
    self.kind = kind
    self.symbolName = symbolName
    self.canEject = canEject
    self.canRemove = canRemove
    self.isMissing = isMissing
  }
}

/// A section of the sidebar, in the order it is shown.
public enum SidebarSection: String, Sendable, CaseIterable {
  case favorites = "Favorites"
  case locations = "Locations"
  case cloud = "Cloud"
  case tags = "Tags"
}

/// A section with its items.
public struct SidebarSectionContent: Sendable, Equatable {
  public let section: SidebarSection
  public let items: [SidebarItem]

  public init(section: SidebarSection, items: [SidebarItem]) {
    self.section = section
    self.items = items
  }
}

/// A mounted volume, as a source reports it.
public struct VolumeInfo: Sendable, Equatable {
  public let url: URL
  public let name: String
  public let isEjectable: Bool

  public init(url: URL, name: String, isEjectable: Bool) {
    self.url = url
    self.name = name
    self.isEjectable = isEjectable
  }
}

/// A folder a cloud service keeps on this Mac.
public struct CloudFolder: Sendable, Equatable {
  public let url: URL
  public let name: String
  /// iCloud Drive is shown first.
  public let isICloudDrive: Bool

  public init(url: URL, name: String, isICloudDrive: Bool = false) {
    self.url = url
    self.name = name
    self.isICloudDrive = isICloudDrive
  }
}

/// A tag that is in use, and how many files carry it.
public struct TagInfo: Sendable, Equatable {
  public let name: String
  public let count: Int

  public init(name: String, count: Int) {
    self.name = name
    self.count = count
  }
}

/// Builds the sidebar from what its sources answered. A pure function: no
/// source is asked here, so it is tested without a disk or a window.
public enum SidebarBuilder {
  public static func sections(
    favorites: [ResolvedFavorite], volumes: [VolumeInfo], cloud: [CloudFolder], tags: [TagInfo]
  ) -> [SidebarSectionContent] {
    var favoriteItems = [
      SidebarItem(
        id: "recents", title: "Recents", location: VirtualLocation.recents.url, kind: .recents,
        symbolName: "clock")
    ]
    favoriteItems += favorites.map { favorite in
      SidebarItem(
        id: "favorite:\(favorite.id)", title: favorite.name,
        location: favorite.url ?? URL(filePath: "/", directoryHint: .isDirectory),
        kind: .favorite, symbolName: "folder", canRemove: true, isMissing: favorite.url == nil)
    }

    let volumeItems = volumes.map { volume in
      SidebarItem(
        id: "volume:\(volume.url.path)", title: volume.name, location: volume.url,
        kind: .volume, symbolName: volume.isEjectable ? "externaldrive" : "internaldrive",
        canEject: volume.isEjectable)
    }

    let cloudItems = cloud.sorted { lhs, rhs in
      if lhs.isICloudDrive != rhs.isICloudDrive { return lhs.isICloudDrive }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }.map { folder in
      SidebarItem(
        id: "cloud:\(folder.url.path)", title: folder.name, location: folder.url, kind: .cloud,
        symbolName: folder.isICloudDrive ? "icloud" : "cloud")
    }

    let tagItems = tags.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }.map { tag in
      SidebarItem(
        id: "tag:\(tag.name)", title: tag.name, location: VirtualLocation.tag(tag.name).url,
        kind: .tag, symbolName: "tag")
    }

    // A section with nothing in it is not shown, except Favorites, which
    // always has Recents.
    return [
      SidebarSectionContent(section: .favorites, items: favoriteItems),
      SidebarSectionContent(section: .locations, items: volumeItems),
      SidebarSectionContent(section: .cloud, items: cloudItems),
      SidebarSectionContent(section: .tags, items: tagItems),
    ].filter { !$0.items.isEmpty }
  }
}
