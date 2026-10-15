import AppKit
import Testing

@testable import BrowserUI

@Suite struct SidebarSelectionColorTests {
  /// The system's accent colors, as sRGB, and the extremes.
  private static let accents: [(String, NSColor)] = [
    ("blue", NSColor(srgbRed: 0, green: 0.455, blue: 0.976, alpha: 1)),
    ("purple", NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1)),
    ("pink", NSColor(srgbRed: 0.97, green: 0.31, blue: 0.51, alpha: 1)),
    ("red", NSColor(srgbRed: 1, green: 0.32, blue: 0.27, alpha: 1)),
    ("orange", NSColor(srgbRed: 0.97, green: 0.51, blue: 0.1, alpha: 1)),
    ("yellow", NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)),
    ("green", NSColor(srgbRed: 0.4, green: 0.8, blue: 0.2, alpha: 1)),
    ("graphite", NSColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)),
    ("white", NSColor.white),
    ("black", NSColor.black),
  ]

  @Test(arguments: accents)
  func whiteTextOnTheFillReachesTheBarForEveryAccent(accent: (String, NSColor)) throws {
    let fill = try #require(SidebarSelectionColor.fill(for: accent.1).usingColorSpace(.sRGB))
    let contrast = SidebarSelectionColor.contrastWithWhite(
      red: Double(fill.redComponent), green: Double(fill.greenComponent),
      blue: Double(fill.blueComponent))
    #expect(contrast >= 4.5, "\(accent.0): \(contrast)")
  }

  @Test func theDefaultBlueIsDarkenedAndKeepsItsHue() throws {
    let blue = NSColor(srgbRed: 0, green: 0.455, blue: 0.976, alpha: 1)
    let fill = try #require(SidebarSelectionColor.fill(for: blue).usingColorSpace(.sRGB))
    #expect(fill.blueComponent > fill.greenComponent)
    #expect(fill.blueComponent < 0.976)
    #expect(fill.redComponent == 0)
  }

  @Test func anAccentThatAlreadyPassesIsLeftAlone() throws {
    let dark = NSColor(srgbRed: 0, green: 0.2, blue: 0.5, alpha: 1)
    let fill = try #require(SidebarSelectionColor.fill(for: dark).usingColorSpace(.sRGB))
    #expect(abs(fill.blueComponent - 0.5) < 0.001)
  }
}
