import SwiftUI

/// The content of the Settings window: one checkbox, and a line that says
/// what it does. Hosted in an AppKit window by the app.
public struct SettingsView: View {
  /// The words of the setting, shown beside the checkbox.
  public static let rememberOpenFoldersTitle = "Open folders again when going back or forward"
  /// What the setting does, in a sentence.
  public static let rememberOpenFoldersExplanation =
    "When you go back or forward to a folder, the folders that were open inside it open again."

  private let settings: BrowserSettings
  @State private var remembersOpenFolders: Bool

  public init(settings: BrowserSettings = BrowserSettings()) {
    self.settings = settings
    _remembersOpenFolders = State(initialValue: settings.rememberOpenFolders)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(Self.rememberOpenFoldersTitle, isOn: $remembersOpenFolders)
        .apply(.rememberOpenFoldersToggle)
      // Primary text color: dimmer text fails the contrast audit.
      Text(Self.rememberOpenFoldersExplanation)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(width: 440, alignment: .leading)
    .onChange(of: remembersOpenFolders) { _, newValue in
      settings.rememberOpenFolders = newValue
    }
  }
}
