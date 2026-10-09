import AppKit
import FileMetadata
import FileOperations
import FileSystemCore

/// Shows the contents of one folder. Every pane hosts one of these.
///
/// Phase 0 step 3 is a stub: it holds a location and an empty view. The list
/// view arrives with the walking skeleton in step 5.
@MainActor
public final class BrowserViewController: NSViewController {
  /// The folder this browser shows.
  public private(set) var location: URL

  public init(location: URL) {
    self.location = location
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("BrowserViewController is created in code")
  }

  public override func loadView() {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    view.identifier = NSUserInterfaceItemIdentifier("browser-view")
    self.view = view
  }
}
