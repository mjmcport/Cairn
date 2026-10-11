# Cairn

A native Mac file manager in Swift and AppKit. The full plan is the Claude Doc "Mac file manager implementation plan". Work follows its phases and steps, one commit per step.

## Decisions (settled)

| Decision | Value |
| --- | --- |
| Name | **Cairn** |
| Repo | `mjmcport/Cairn`, **private**, personal account |
| License | MIT, `Copyright (c) 2026 Matthew McGuire` |
| Bundle ID | `com.mjmcport.cairn` (confirm before the first signed build) |
| Minimum macOS | **15 Sequoia** |
| Newer OS features | Adopt macOS 26 capabilities behind `#available(macOS 26, *)` with a working macOS 15 fallback. Never raise the floor just for one feature |
| CPU | Apple Silicon (arm64) only |
| Language / UI | Swift 6, strict concurrency. AppKit for file views, SwiftUI hosted in AppKit for inspector and settings |
| Project file | XcodeGen from `project.yml`; `.xcodeproj` not committed |
| Tests | Swift Testing (unit), XCTest (performance), XCUITest (end-to-end). Tests ship in the same commit as the code |
| Distribution | Developer ID, notarized, hardened runtime, not sandboxed. Sparkle 2 for updates |
| Dependencies | MIT, BSD, Apache-2.0 or zlib only |
| Workflow | One git commit per step, tests included, compound engineering loop. Pushing, CI and branches follow "CI, pushing and branches" below |

Because the floor is 15, use the Observation framework and newer AppKit APIs freely, with no macOS 14 guards.

## Rules that hold in every step

- No file-system call on the main thread. Every file-system entry point starts with `MainThreadGuard.assertOffMainThread()`.
- Log through `Log` (FileSystemCore). Paths and file names stay private in logs.
- `FileSystemCore`, `FileMetadata` and `FileOperations` never import AppKit. Only `BrowserUI` and the app target do.
- Clean room: no code from GPL projects (Nimble Commander is GPL-3) or closed-source apps.
- Every control gets an accessibility label and identifier, through `AccessibilityElement` and `apply(_:)` only.
- No telemetry, and no networking outside the update checker.
- Tests touch only temporary fixture folders.

## The loop for each step

1. **Plan:** write `plans/phase-N-step-NN-<name>.md`, tests included.
2. **Work:** implement with unit tests, and end-to-end tests when the step touches the app.
3. **Review:** run the review pass and fix the findings.
4. **Compound:** record what was learned in `docs/solutions/`.
5. **Commit:** one commit, message `Phase N step N: <name>`. Do not push here; see the next section.

Read `docs/solutions/` before planning a step.

## CI, pushing and branches

- Never start a new step or push on top of a red CI run. After each push, wait for CI with `gh run watch` and fix a red run before continuing.
- Commit after every step. Push at milestones, not after every commit.
- Starting in Phase 1, work on a branch and open a pull request. Merge only when CI is green, so `main` stays green.
- A weekly workflow, `.github/workflows/macos-15.yml`, builds the app and runs the unit tests and the accessibility end-to-end tests on a macOS 15 runner. Before merging a step that leans on AppKit behaviour, run every end-to-end test there by hand: `gh workflow run macos-15.yml --ref <branch>`. Treat a red weekly run like red CI: fix it before starting a new step. If it is unstable or its cost passes about 300 billed minutes a month, tell the user; do not drop a test to fix either.

## Repository layout

```
App/                  AppKit app target: app delegate, windows, controllers
Packages/
  FileSystemCore/     items, directory enumeration, change watching, volumes (no UI)
  FileMetadata/       resource-key groups, extended attributes, ACLs, cloud state
  FileOperations/     copy, move, trash, rename, undo journal, progress
  BrowserUI/          AppKit views and controllers shared by every pane
  TestSupport/        fixture-tree builder and test helpers
UITests/              XCUITest end-to-end suite
project.yml           XcodeGen spec
.github/workflows/    CI, and the weekly macOS 15 check
docs/adr/             architecture decision records
docs/performance/     committed performance baseline
docs/solutions/       lessons captured after each step
plans/                one plan per step
scripts/              repository checks
```

## Toolchain

Recorded 2026-10-09 on the development Mac.

| Tool | Version |
| --- | --- |
| Host macOS | 27.0 (26A5388g), arm64 |
| Xcode | 26.6 (17F113), at `/Applications/Xcode.app` |
| Swift | 6.4 (swiftlang-6.4.0.27.1), from the Command Line Tools |
| XcodeGen | 2.46.0 (Homebrew) |
| Signing identity | None yet |
| Compound engineering plugin | 3.30.4 (`every-marketplace`) |

Three macOS versions matter: the CI runner is macOS 26 (runner label `macos-26`), the development Mac is macOS 27, and the minimum supported is macOS 15. Accessibility and UI behavior can differ between them, so a local pass does not mean CI will pass.

## Status

Phase 0 is complete (12 steps, one commit each). Its plans are in `plans/` and its lessons in `docs/solutions/`. The Phase 0 follow-up (`plans/phase-0-follow-up.md`) closes it out. Phase 1 (Finder-replacement core) is under way, on branches and pull requests. Its first milestone is planned in `plans/phase-1a-browse.md`, which also holds the Phase 1 exit requirements. Milestone 1A step 1 (navigation history, `plans/phase-1a-step-01-navigation-history.md`), step 2 (tabs, `plans/phase-1a-step-02-tabs.md`) and step 3 (fast first rows, `plans/phase-1a-step-03-fast-first-rows.md`) are done. Step 4 is next.

## Open items

- Branch protection on `main` is not enabled: GitHub's free plan refuses it on a private repository. Run `scripts/protect-main.sh` after upgrading to GitHub Pro or making the repository public.
- Confirm the bundle ID before the first signed build.
- Apple Developer Program membership is needed by the end of Phase 1, not for Phase 0. Developer ID signing and notarization are Phase 1 exit requirements (`plans/phase-1a-browse.md`); until then the CI build is signed ad hoc and is not a release.
