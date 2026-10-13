import AppKit

/// The collection view of the icon presentation. It adds the two things
/// `NSCollectionView` does not do: typing selects by name, and a
/// double-click opens.
@MainActor
final class IconCollectionView: NSCollectionView {
  /// Called with characters that were typed and the time of the event.
  var onType: ((String, TimeInterval) -> Void)?
  /// Called after a double-click.
  var onOpen: (() -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    let command = event.modifierFlags.intersection([.command, .control, .option])
    if command.isEmpty, let text = event.characters, !text.isEmpty,
      text.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "."
      })
    {
      onType?(text, event.timestamp)
      return
    }
    super.keyDown(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    if event.clickCount == 2 {
      onOpen?()
    }
  }
}
