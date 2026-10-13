import AppKit
import FileSystemCore

/// The last column of the column presentation: what is known of the file or
/// files selected. A picture where there is one, the name, and a few facts
/// as words.
///
/// It is configured for each selection and not rebuilt. Nothing is read from
/// a file that is online only, and several items make no pictures.
@MainActor
final class PreviewViewController: NSViewController {
  /// The picture is this many points on a side.
  static let pictureSide: CGFloat = 192

  private let loader: ThumbnailLoader
  private let icons: GenericIcons
  private let picture = NSImageView()
  private let badge = NSImageView()
  private let name = NSTextField(wrappingLabelWithString: "")
  private let factsStack = NSStackView()
  private var request: Task<Void, Never>?
  private var shown: [FileItem] = []

  /// What is showing, for tests.
  private(set) var shownName = ""
  private(set) var shownFacts: [String] = []
  private(set) var showsGenericIcon = true
  var showsCloudMark: Bool { !badge.isHidden }

  init(loader: ThumbnailLoader, icons: GenericIcons) {
    self.loader = loader
    self.icons = icons
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("PreviewViewController is created in code")
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
    root.applyIdentifier(of: .preview)

    picture.imageScaling = .scaleProportionallyUpOrDown
    picture.translatesAutoresizingMaskIntoConstraints = false
    badge.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: nil)
    badge.contentTintColor = .labelColor
    badge.isHidden = true
    badge.setSpokenText("Online only")
    badge.translatesAutoresizingMaskIntoConstraints = false

    name.font = .boldSystemFont(ofSize: 14)
    name.alignment = .center
    name.textColor = .labelColor
    name.applyIdentifier(of: .previewName)
    name.translatesAutoresizingMaskIntoConstraints = false

    factsStack.orientation = .vertical
    factsStack.alignment = .leading
    factsStack.spacing = 4
    factsStack.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(picture)
    root.addSubview(badge)
    root.addSubview(name)
    root.addSubview(factsStack)
    NSLayoutConstraint.activate([
      picture.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
      picture.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      picture.widthAnchor.constraint(equalToConstant: Self.pictureSide),
      picture.heightAnchor.constraint(equalToConstant: Self.pictureSide),
      badge.trailingAnchor.constraint(equalTo: picture.trailingAnchor),
      badge.bottomAnchor.constraint(equalTo: picture.bottomAnchor),
      badge.widthAnchor.constraint(equalToConstant: 28),
      badge.heightAnchor.constraint(equalToConstant: 28),
      name.topAnchor.constraint(equalTo: picture.bottomAnchor, constant: 12),
      name.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      name.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      factsStack.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 12),
      factsStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      factsStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
    ])
    view = root
  }

  // MARK: Showing

  /// Shows what is known of `items`: one file, several, or nothing.
  func show(_ items: [FileItem]) {
    _ = view
    request?.cancel()
    request = nil
    shown = items
    badge.isHidden = true
    showsGenericIcon = true

    switch items.count {
    case 0:
      setPicture(nil, saying: "No preview")
      set(name: "", facts: [])
    case 1:
      show(one: items[0])
    default:
      setPicture(NSImage(named: NSImage.multipleDocumentsName), saying: "Several items")
      let total = items.compactMap(\.size).reduce(0, +)
      set(
        name: "\(items.count) items",
        facts: ["Total size: \(Self.byteText(total))"])
    }
  }

  private func show(one item: FileItem) {
    setPicture(icons.icon(for: item), saying: "Preview of \(item.name)")
    badge.isHidden = !item.isOnlineOnly
    set(name: item.name, facts: Self.facts(for: item))
    guard !item.isOnlineOnly, item.kind != .directory else { return }
    let side = Self.pictureSide
    let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    request = Task { [weak self, loader] in
      let image = await loader.picture(
        for: item, pointSize: CGSize(width: side, height: side), scale: scale)
      guard let self, !Task.isCancelled, self.shown == [item], let image else { return }
      self.setPicture(
        NSImage(cgImage: image, size: NSSize(width: side, height: side)),
        saying: "Preview of \(item.name)")
      self.showsGenericIcon = false
    }
  }

  /// Shows `image` and says `description` for it. The audit reads an image's
  /// description from the image, not from the view that shows it, and a
  /// shared icon is copied so that its description is this one's.
  private func setPicture(_ image: NSImage?, saying description: String) {
    let own = image.flatMap { $0.copy() as? NSImage }
    own?.accessibilityDescription = description
    picture.image = own
    picture.setSpokenText(description)
  }

  private func set(name text: String, facts: [String]) {
    shownName = text
    shownFacts = facts
    name.stringValue = text
    for view in factsStack.arrangedSubviews {
      factsStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for fact in facts {
      let label = NSTextField(wrappingLabelWithString: fact)
      label.font = .systemFont(ofSize: 12)
      label.textColor = .labelColor
      label.applyIdentifier(of: .previewFact)
      factsStack.addArrangedSubview(label)
    }
  }

  // MARK: What is said

  /// The facts of one item, each as words that can be spoken.
  static func facts(for item: FileItem) -> [String] {
    let kind: String =
      switch item.kind {
      case .directory: "Folder"
      case .package: "Package"
      case .symbolicLink: "Link"
      case .file:
        GenericIcons.contentType(for: item).localizedDescription ?? "File"
      }
    var facts = ["Kind: \(kind)"]
    if item.isOnlineOnly {
      facts.append("Availability: Online only, not on this Mac")
    }
    facts.append("Size: \(item.size.map(byteText) ?? "Not available")")
    facts.append("Size on Disk: \(item.allocatedSize.map(byteText) ?? "Not available")")
    facts.append("Modified: \(dateText(item.modificationDate))")
    facts.append("Added: \(dateText(item.dateAdded))")
    return facts
  }

  private static func byteText(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
  }

  private static func dateText(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "Not available"
  }
}
