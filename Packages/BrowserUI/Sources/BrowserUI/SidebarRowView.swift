import AppKit

/// The color a selected sidebar row is filled with.
///
/// The system fills a selected row with the accent color and draws white
/// text on it. With the default blue that is about 4.3:1 on macOS 26, under
/// the 4.5:1 bar for text this size, and other accent colors are worse
/// (yellow is under 2:1). The fill is the accent darkened until white text
/// on it reaches the bar, so the selected state passes on every accent.
enum SidebarSelectionColor {
  /// The least contrast of white text on the fill.
  static let minimumContrast = 4.6

  /// The relative luminance of an sRGB color, as WCAG defines it.
  static func luminance(red: Double, green: Double, blue: Double) -> Double {
    func linear(_ value: Double) -> Double {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// White text's contrast against a color with these components.
  static func contrastWithWhite(red: Double, green: Double, blue: Double) -> Double {
    1.05 / (luminance(red: red, green: green, blue: blue) + 0.05)
  }

  /// The accent, darkened in small steps of black until white text on it
  /// reaches ``minimumContrast``.
  static func fill(for accent: NSColor) -> NSColor {
    let base = accent.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0.3, blue: 0.7, alpha: 1)
    let red = Double(base.redComponent)
    let green = Double(base.greenComponent)
    let blue = Double(base.blueComponent)
    var keep = 1.0
    while keep > 0,
      contrastWithWhite(red: red * keep, green: green * keep, blue: blue * keep) < minimumContrast
    {
      keep -= 0.02
    }
    keep = max(keep, 0)
    return NSColor(
      srgbRed: red * keep, green: green * keep, blue: blue * keep, alpha: 1)
  }
}

/// A sidebar row that draws its selection itself, in
/// ``SidebarSelectionColor``, and always speaks to its cell as emphasized so
/// the row's text is white on it, focused or not.
final class SidebarRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard isSelected else { return }
    var fill = NSColor.black
    effectiveAppearance.performAsCurrentDrawingAppearance {
      fill = SidebarSelectionColor.fill(for: .controlAccentColor)
    }
    fill.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
  }

  override var interiorBackgroundStyle: NSView.BackgroundStyle {
    isSelected ? .emphasized : super.interiorBackgroundStyle
  }
}
