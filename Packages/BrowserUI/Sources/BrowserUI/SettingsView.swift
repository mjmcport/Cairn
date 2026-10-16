import SwiftUI

/// The content of the Settings window: one checkbox, and a line that says
/// what it does. Hosted in an AppKit window by the app.
public struct SettingsView: View {
  /// The words of the setting, shown beside the checkbox.
  public static let rememberOpenFoldersTitle = "Open folders again when going back or forward"
  /// What the setting does, in a sentence.
  public static let rememberOpenFoldersExplanation =
    "When you go back or forward to a folder, the folders that were open inside it open again."

  /// The words of the restoration setting, shown beside its checkbox.
  public static let restoresWindowsTitle = "Reopen windows and tabs when Cairn starts"
  public static let restoresWindowsExplanation =
    "Cairn opens the folders, views and sorting you had when you last quit, or when it last stopped."

  private let settings: BrowserSettings
  private let onRestoresWindowsChange: () -> Void
  @State private var remembersOpenFolders: Bool
  @State private var restoresWindows: Bool

  /// - Parameter onRestoresWindowsChange: Called after the restoration
  ///   setting is written, so the saver can start or stop.
  public init(
    settings: BrowserSettings = BrowserSettings(),
    onRestoresWindowsChange: @escaping () -> Void = {}
  ) {
    self.settings = settings
    self.onRestoresWindowsChange = onRestoresWindowsChange
    _remembersOpenFolders = State(initialValue: settings.rememberOpenFolders)
    _restoresWindows = State(initialValue: settings.restoresWindows)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(Self.rememberOpenFoldersTitle, isOn: $remembersOpenFolders)
        .apply(.rememberOpenFoldersToggle)
      // Primary text color: dimmer text fails the contrast audit.
      Text(Self.rememberOpenFoldersExplanation)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
      Toggle(Self.restoresWindowsTitle, isOn: $restoresWindows)
        .apply(.restoresWindowsToggle)
        .padding(.top, 12)
      Text(Self.restoresWindowsExplanation)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(width: 440, alignment: .leading)
    .onChange(of: remembersOpenFolders) { _, newValue in
      settings.rememberOpenFolders = newValue
    }
    .onChange(of: restoresWindows) { _, newValue in
      settings.restoresWindows = newValue
      onRestoresWindowsChange()
    }
  }
}
