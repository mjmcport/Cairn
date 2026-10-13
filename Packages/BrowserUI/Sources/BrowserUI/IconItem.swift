import AppKit
import FileSystemCore

/// One cell of the icon presentation: a picture above a name, with a cloud
/// mark on the picture of a file that is online only.
@MainActor
final class IconItem: NSCollectionViewItem {
  /// The reuse identifier of the collection view's cell cache, not an
  /// accessibility identity.
  static let reuseIdentifier = NSUserInterfaceItemIdentifier(rawValue: "icon-item")
  /// The picture is this many points on a side.
  static let pictureSide: CGFloat = 64
  /// The size of a cell.
  static let cellSize = NSSize(width: 104, height: 112)

  private let picture = NSImageView()
  private let badge = NSImageView()
  private let name = NSTextField(wrappingLabelWithString: "")
  private(set) var item: FileItem?
  private var loading: Task<Void, Never>?

  /// Whether the picture on screen is the generic icon, and not one made
  /// from the file.
  private(set) var showsGenericIcon = true

  override func loadView() {
    let root = NSView(frame: NSRect(origin: .zero, size: Self.cellSize))
    root.wantsLayer = true
    root.layer?.cornerRadius = 6
    root.applyIdentifier(of: .iconCell)

    // The cell speaks for itself: name, kind and whether it is on this Mac.
    // The picture and the cloud mark are decoration, so they are not
    // elements of their own, which the audit would ask to be described.
    root.setAccessibilityElement(true)
    root.setAccessibilityRole(.group)
    root.setAccessibilityChildren([])
    picture.setAccessibilityElement(false)
    badge.setAccessibilityElement(false)

    picture.imageScaling = .scaleProportionallyUpOrDown
    picture.translatesAutoresizingMaskIntoConstraints = false
    badge.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: nil)
    badge.contentTintColor = .labelColor
    badge.isHidden = true
    badge.translatesAutoresizingMaskIntoConstraints = false
    name.alignment = .center
    name.maximumNumberOfLines = 2
    name.lineBreakMode = .byTruncatingMiddle
    name.font = .systemFont(ofSize: 12)
    name.textColor = .labelColor
    name.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(picture)
    root.addSubview(badge)
    root.addSubview(name)
    NSLayoutConstraint.activate([
      picture.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
      picture.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      picture.widthAnchor.constraint(equalToConstant: Self.pictureSide),
      picture.heightAnchor.constraint(equalToConstant: Self.pictureSide),
      badge.trailingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 4),
      badge.bottomAnchor.constraint(equalTo: picture.bottomAnchor, constant: 4),
      badge.widthAnchor.constraint(equalToConstant: 18),
      badge.heightAnchor.constraint(equalToConstant: 18),
      name.topAnchor.constraint(equalTo: picture.bottomAnchor, constant: 4),
      name.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
      name.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
    ])
    view = root
  }

  override var isSelected: Bool {
    didSet { updateSelection() }
  }

  /// Shows `item` with `icon`, its generic picture, at once.
  func configure(item: FileItem, icon: NSImage) {
    stopLoading()
    self.item = item
    picture.image = icon
    showsGenericIcon = true
    name.stringValue = item.name
    badge.isHidden = !item.isOnlineOnly
    view.setSpokenText(Self.spokenText(for: item))
    updateSelection()
  }

  /// What VoiceOver says: the name, what kind of thing it is, and whether it
  /// is on this Mac.
  static func spokenText(for item: FileItem) -> String {
    let kind =
      switch item.kind {
      case .directory: "folder"
      case .package: "package"
      case .symbolicLink: "link"
      case .file: "file"
      }
    return item.isOnlineOnly ? "\(item.name), \(kind), online only" : "\(item.name), \(kind)"
  }

  /// Asks for the picture made from the file. Does nothing for an online-only
  /// item: nothing is read from such a file to draw it.
  func startLoading(with loader: ThumbnailLoader, scale: CGFloat) {
    guard let item, !item.isOnlineOnly, loading == nil, showsGenericIcon else { return }
    let side = Self.pictureSide
    loading = Task { [weak self] in
      let image = await loader.picture(
        for: item, pointSize: CGSize(width: side, height: side), scale: scale)
      guard let self, !Task.isCancelled, self.item == item, let image else { return }
      self.picture.image = NSImage(cgImage: image, size: NSSize(width: side, height: side))
      self.showsGenericIcon = false
      self.loading = nil
    }
  }

  func stopLoading() {
    loading?.cancel()
    loading = nil
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    stopLoading()
    item = nil
    picture.image = nil
    badge.isHidden = true
  }

  private func updateSelection() {
    view.layer?.backgroundColor =
      isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
    name.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
  }
}
