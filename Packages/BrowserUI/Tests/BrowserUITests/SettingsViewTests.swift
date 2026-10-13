import AppKit
import SwiftUI
import Testing

@testable import BrowserUI

/// What a unit test can see of the Settings view. SwiftUI builds its
/// accessibility tree only when assistive technology asks for it, so an
/// in-process search of that tree finds nothing; whether the checkbox is
/// found by its identifier is the end-to-end test's question
/// (plans/phase-1a-step-05-list-view.md, Open Questions).
@Suite @MainActor struct SettingsViewTests {
  private func suite() throws -> (UserDefaults, cleanup: () -> Void) {
    let name = "SettingsViewTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return (defaults, { defaults.removePersistentDomain(forName: name) })
  }

  @Test func theWordsOnTheCheckboxAreTheWordsItSpeaks() {
    let element = AccessibilityElement.rememberOpenFoldersToggle
    #expect(SettingsView.rememberOpenFoldersTitle == element.label)
    #expect(element.identifier == "setting-remember-open-folders")
    #expect(AccessibilityElement.all.contains(element))
  }

  @Test func theViewHostsInAWindowWithARoomySizeAndWritesNothingUntilChanged() throws {
    let (defaults, cleanup) = try suite()
    defer { cleanup() }
    defaults.set(false, forKey: BrowserSettings.rememberOpenFoldersKey)
    let hosting = NSHostingController(
      rootView: SettingsView(settings: BrowserSettings(defaults: defaults)))
    let window = NSWindow(contentViewController: hosting)
    defer { window.close() }
    window.orderFront(nil)
    hosting.view.layoutSubtreeIfNeeded()

    #expect(hosting.view.fittingSize.width >= 400)
    #expect(hosting.view.fittingSize.height > 0)
    // Showing the view reads the setting and does not write it.
    #expect(defaults.object(forKey: BrowserSettings.rememberOpenFoldersKey) as? Bool == false)
  }
}
