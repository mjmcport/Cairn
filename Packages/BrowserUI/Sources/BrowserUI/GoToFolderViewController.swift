import AppKit
import FileSystemCore

/// The sheet behind Go > Go to Folder: a field for a typed path, the folders
/// that complete it, and a line that says what is wrong. Nothing moves until
/// the person presses Return or Go.
@MainActor
public final class GoToFolderViewController: NSViewController {
  private let base: URL
  private let home: URL
  private let completer: any FolderCompleting

  /// Called with the folder to show, and the file to select in it when the
  /// typed place was a file. The sheet has been dismissed.
  public var onGo: ((URL, Set<URL>) -> Void)?

  let field = NSTextField()
  private let table = NSTableView()
  private let scrollView = NSScrollView()
  let status = NSTextField(labelWithString: "")
  private let goButton = NSButton(title: "Go", target: nil, action: nil)
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

  /// What is offered for the text now in the field.
  private(set) var suggestions: [FolderSuggestion] = []
  /// Ticks for each request, so an answer for older text is dropped.
  private var generation = 0
  private var requestTask: Task<Void, Never>?
  private var submitTask: Task<Void, Never>?

  public init(
    base: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
    completer: any FolderCompleting = DirectoryFolderCompleter()
  ) {
    self.base = base
    self.home = home
    self.completer = completer
    super.init(nibName: nil, bundle: nil)
    title = "Go to Folder"
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("GoToFolderViewController is created in code")
  }

  public override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 260))
    let heading = NSTextField(labelWithString: "Go to the folder:")
    for view in [heading, field, scrollView, status, goButton, cancelButton] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)
    }
    field.delegate = self
    field.placeholderString = "~/Documents"
    field.apply(.goToFolderField)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "folder"))
    table.addTableColumn(column)
    table.headerView = nil
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(completeSelection)
    table.apply(.goToFolderSuggestions)
    scrollView.documentView = table
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder

    // The label color, not the secondary one: the secondary gray is about
    // 3.9:1 on the sheet's white and fails the audit.
    status.textColor = .labelColor
    status.lineBreakMode = .byWordWrapping
    status.applyIdentifier(of: .goToFolderStatus)

    goButton.keyEquivalent = "\r"
    goButton.target = self
    goButton.action = #selector(go(_:))
    goButton.apply(.goToFolderGoButton)
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.target = self
    cancelButton.action = #selector(cancel(_:))
    cancelButton.apply(.goToFolderCancelButton)

    NSLayoutConstraint.activate([
      heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
      heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      field.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
      field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      scrollView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: field.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: field.trailingAnchor),
      scrollView.heightAnchor.constraint(equalToConstant: 120),
      status.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
      status.leadingAnchor.constraint(equalTo: field.leadingAnchor),
      status.trailingAnchor.constraint(equalTo: field.trailingAnchor),
      goButton.trailingAnchor.constraint(equalTo: field.trailingAnchor),
      goButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
      cancelButton.trailingAnchor.constraint(equalTo: goButton.leadingAnchor, constant: -8),
      cancelButton.bottomAnchor.constraint(equalTo: goButton.bottomAnchor),
    ])
    view = container
    field.stringValue = TypedPath.text(for: base)
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.apply(.goToFolderSheet)
    view.window?.makeFirstResponder(field)
    field.currentEditor()?.selectAll(nil)
    textDidChange()
  }

  // MARK: Completion

  /// Asks for the folders that complete the text in the field.
  func textDidChange() {
    generation += 1
    let ticket = generation
    let (folder, prefix) = TypedPath.completionContext(
      field.stringValue, relativeTo: base, home: home)
    let completer = completer
    requestTask?.cancel()
    requestTask = Task { [weak self] in
      let found: [FolderSuggestion]? = await Task.detached {
        try? completer.folders(
          in: folder, prefix: prefix, limit: DirectoryFolderCompleter.suggestionLimit)
      }.value
      guard !Task.isCancelled, let self, self.generation == ticket else { return }
      self.show(found ?? [])
    }
  }

  /// Waits for the last request to finish. Tests use it.
  func settle() async {
    await requestTask?.value
    await submitTask?.value
  }

  private func show(_ found: [FolderSuggestion]) {
    suggestions = found
    table.reloadData()
    switch found.count {
    case 0: status.stringValue = ""
    case 1: status.stringValue = "1 folder matches."
    default: status.stringValue = "\(found.count) folders match."
    }
    if !found.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
  }

  private func moveSelection(by step: Int) {
    guard !suggestions.isEmpty else { return }
    let row = min(max(table.selectedRow + step, 0), suggestions.count - 1)
    table.selectRowIndexes([row], byExtendingSelection: false)
    table.scrollRowToVisible(row)
  }

  /// Puts the chosen folder's path in the field, ready to go on typing.
  @objc func completeSelection() {
    let row = table.selectedRow
    guard suggestions.indices.contains(row) else { return }
    field.stringValue = TypedPath.text(for: suggestions[row].url)
    field.currentEditor()?.moveToEndOfLine(nil)
    textDidChange()
  }

  // MARK: Going

  @objc func go(_ sender: Any?) {
    let url = TypedPath.resolve(field.stringValue, relativeTo: base, home: home)
    let completer = completer
    submitTask?.cancel()
    submitTask = Task { [weak self] in
      let existence = await Task.detached { completer.existence(of: url) }.value
      guard !Task.isCancelled, let self else { return }
      switch existence {
      case .folder:
        self.finish(url, selecting: [])
      case .file:
        self.finish(url.deletingLastPathComponent(), selecting: [url])
      case .missing:
        self.status.stringValue = "There is no folder or file at that path."
      }
    }
  }

  private func finish(_ folder: URL, selecting: Set<URL>) {
    let onGo = onGo
    dismiss(nil)
    onGo?(folder, selecting)
  }

  @objc func cancel(_ sender: Any?) {
    dismiss(nil)
  }
}

extension GoToFolderViewController: NSTextFieldDelegate {
  public func controlTextDidChange(_ obj: Notification) {
    textDidChange()
  }

  public func control(
    _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
  ) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(by: 1)
      return true
    case #selector(NSResponder.moveUp(_:)):
      moveSelection(by: -1)
      return true
    case #selector(NSResponder.insertTab(_:)):
      completeSelection()
      return true
    case #selector(NSResponder.insertNewline(_:)):
      go(nil)
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      cancel(nil)
      return true
    default:
      return false
    }
  }
}

extension GoToFolderViewController: NSTableViewDataSource, NSTableViewDelegate {
  public func numberOfRows(in tableView: NSTableView) -> Int { suggestions.count }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    let label = NSTextField(labelWithString: suggestions[row].name)
    label.lineBreakMode = .byTruncatingMiddle
    return label
  }
}
