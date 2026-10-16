import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// A restored window opens at once and lists once its place is known
/// (plans/phase-1a-step-10-state-restoration.md, U4: KTD3, R7, R17).
@Suite @MainActor struct RestoreAtLaunchTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private let gone = URL(filePath: "/fixture/root/gone", directoryHint: .isDirectory)
  private let other = URL(filePath: "/fixture/other", directoryHint: .isDirectory)

  private func reader() -> StubReader {
    StubReader(results: [
      root: [FileItem(url: root.appending(path: "a.txt"), kind: .file)],
      other: [FileItem(url: other.appending(path: "o.txt"), kind: .file)],
    ])
  }

  /// A resolver that holds at a gate, then moves `gone` to `root`.
  private func gatedResolver(_ gate: Gate, calls: Recorded<[String]>) -> RestoredLocation.Resolver {
    { saved in
      calls.update { $0.append(saved.location) }
      await gate.pass()
      var result = saved
      if saved.location == "file:///fixture/root/gone/" {
        result.location = "file:///fixture/root/"
      }
      return result
    }
  }

  @Test func theShowingTabLoadsThenListsTheResolvedPlaceAndNothingListedBefore() async throws {
    let reader = reader()
    let gate = Gate()
    let calls = Recorded<[String]>([])
    let saved = SavedWindow(
      tabs: [
        SavedTab(location: gone.absoluteString, viewMode: .icons),
        SavedTab(location: other.absoluteString),
      ], showingIndex: 0)
    let pane = PaneViewController(
      location: root, reader: reader, watcher: nil, restoring: saved,
      resolver: gatedResolver(gate, calls: calls))
    let window = NSWindow(contentViewController: pane)
    _ = window
    await gate.waitUntilReached()

    let browser = pane.showingBrowser
    // Open, titled, and loading: no listing of the missing folder or any other.
    #expect(browser.model.state == .loading)
    #expect(reader.listings(of: gone) == 0)
    #expect(reader.listings(of: root) == 0)
    // While unresolved, the tab saves what it was given, untouched.
    #expect(browser.captureState() == saved.tabs[0])

    await gate.open()
    await browser.loadTask?.value
    #expect(browser.model.location == root)
    #expect(browser.model.viewMode == .icons)
    #expect(reader.listings(of: gone) == 0)
    #expect(reader.listings(of: root) == 1)
    #expect(browser.model.state == .loaded)
    // The tab that never showed has been neither resolved nor listed (R18).
    #expect(calls.value == [gone.absoluteString])
    #expect(reader.listings(of: other) == 0)
    #expect(pane.captureState().tabs[1] == saved.tabs[1])
  }

  @Test func aTabResolvesWhenItIsFirstShown() async throws {
    let reader = reader()
    let gate = Gate()
    await gate.open()
    let calls = Recorded<[String]>([])
    let saved = SavedWindow(
      tabs: [SavedTab(location: root.absoluteString), SavedTab(location: other.absoluteString)])
    let pane = PaneViewController(
      location: root, reader: reader, watcher: nil, restoring: saved,
      resolver: gatedResolver(gate, calls: calls))
    let window = NSWindow(contentViewController: pane)
    _ = window
    await pane.showingBrowser.loadTask?.value

    pane.showNextTab(nil)
    await pane.showingBrowser.loadTask?.value
    #expect(calls.value == [root.absoluteString, other.absoluteString])
    #expect(reader.listings(of: other) == 1)
  }

  // MARK: Window

  @Test func aSavedFrameOnNoScreenIsMovedOntoOne() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.setFrame(NSRect(x: 40000, y: 40000, width: 800, height: 500), display: false)
    #expect(!NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) })
    WindowFrame.moveOntoAScreen(window)
    #expect(NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) })
    #expect(window.frame.width > 0)
  }

  @Test func theFrameNameCarriesTheSuite() {
    #expect(WindowFrame.autosaveName(suite: nil) == "CairnMainWindow")
    #expect(WindowFrame.autosaveName(suite: "T") == "CairnMainWindow-T")
  }

  @Test func aSavedFrameIsRestoredUnderItsName() throws {
    let name = WindowFrame.autosaveName(suite: "RestoreAtLaunchTests-\(UUID().uuidString)")
    defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)") }
    let first = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 700, height: 450),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    #expect(!WindowFrame.restore(first, named: name))
    first.setFrame(NSRect(x: 120, y: 140, width: 720, height: 460), display: false)
    first.saveFrame(usingName: name)
    // A name belongs to one window at a time.
    first.setFrameAutosaveName("")

    let second = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    #expect(WindowFrame.restore(second, named: name))
    #expect(abs(second.frame.width - 720) < 1)
  }

  // MARK: Sidebar

  @Test func theSidebarsSavedWidthAndCollapseAreRestored() async throws {
    func makeWindow(_ saved: SavedWindow?) async -> (WindowContentViewController, NSWindow) {
      let pane = PaneViewController(location: root, reader: reader(), watcher: nil)
      let content = WindowContentViewController(
        pane: pane, sidebar: SidebarViewController(), restoring: saved)
      let window = NSWindow(contentViewController: content)
      window.setContentSize(NSSize(width: 1100, height: 600))
      content.view.layoutSubtreeIfNeeded()
      return (content, window)
    }

    let (wide, w1) = await makeWindow(SavedWindow(sidebarWidth: 260, tabs: []))
    _ = w1
    #expect(abs((wide.splitView.arrangedSubviews.first?.frame.width ?? 0) - 260) < 2)
    #expect(!(wide.splitViewItems.first?.isCollapsed ?? true))

    let (collapsed, w2) = await makeWindow(SavedWindow(sidebarCollapsed: true, tabs: []))
    _ = w2
    #expect(collapsed.splitViewItems.first?.isCollapsed == true)
  }

  // MARK: Settings

  @Test func theRestorationCheckboxSpeaksItsWords() {
    let element = AccessibilityElement.restoresWindowsToggle
    #expect(SettingsView.restoresWindowsTitle == element.label)
    #expect(element.identifier == "setting-restores-windows")
    #expect(AccessibilityElement.all.contains(element))
  }
}
