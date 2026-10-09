# 1. AppKit for the interface

- Status: Accepted
- Date: 2026-10-09

## Context

A file manager is mostly large lists, outlines and column browsers with drag and drop, type-to-select, inline rename and multiple selection. It has to feel like Finder and stay responsive with 100,000 rows.

## Decision

Build the file views in AppKit (`NSTableView`, `NSOutlineView`, `NSCollectionView`, `NSBrowser`). Use SwiftUI, hosted inside AppKit, only for forms: the Get Info inspector and the settings window. Build the interface in code, with no storyboards or nibs.

## Consequences

- The views get AppKit's mature behavior for selection, drag and drop, keyboard handling and row reuse.
- More code than SwiftUI for the same screen, and AppKit's main-actor rules must be respected by hand.
- AppKit is confined to the app target and `BrowserUI`. Everything below can be tested without a window.
- No storyboard means every view is reviewable as a diff and nothing depends on Interface Builder.

## Alternatives considered

- **SwiftUI throughout.** Its lists and drag and drop are still limiting for file views, and large tables are harder to keep fast.
- **Catalyst or a cross-platform toolkit.** Neither feels native on the Mac, which is a stated goal.
