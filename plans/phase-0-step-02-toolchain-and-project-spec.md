# build: Phase 0 step 2, toolchain and project spec

Date: 2026-10-09

Make a clean clone build with one command, from a project file that is generated rather than committed.

## Acceptance criteria

- [x] `.xcode-version` pins Xcode 26.6
- [x] `project.yml`: app target `Cairn`, bundle ID `com.mjmcport.cairn`, macOS 15.0, arm64 only, Swift 6 with complete concurrency checking, hardened runtime on, sandbox off, warnings as errors
- [x] A minimal AppKit app, built in code with no storyboard: one window and a menu bar
- [x] `Makefile` with `bootstrap`, `generate`, `build`, `test`, `uitest`, `lint`, `clean` and `clean-clone`; `make` alone runs bootstrap, build and test
- [x] `scripts/bootstrap.sh` reports each toolchain problem with the command that fixes it

## Tests

- [x] `scripts/test-clean-clone.sh`: a copy of every tracked and unignored file builds and passes `make all`
- [x] `scripts/check-project-spec.sh`: reads the generated project's build settings for Debug and Release and compares them with the settled decisions
- [x] `scripts/test-bootstrap.sh`: bootstrap rejects a missing Xcode and an Intel Mac
- [x] `UITests/LaunchTests.swift`: the built app launches and shows its window

## Decisions made in this step

- **The Makefile sets `DEVELOPER_DIR`** instead of relying on `xcode-select`, so the build works on a Mac whose selected tools are the Command Line Tools.
- **Signing is ad hoc** ("sign to run locally"). Developer ID signing arrives in Phase 1.
- **`make test` has no Swift unit tests yet.** The app target stays thin, and a test bundle hosted in a hardened-runtime app needs library validation relaxed. Unit tests live in the packages from step 3.
- **Bootstrap fails on a different Xcode major version** and only notes a different minor version, so the CI runner's point release does not block a build.
- **`make lint` uses swift-format's defaults and is not strict.** Step 8 commits a configuration and makes it strict.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 2
- `docs/solutions/2026-10-09-toolchain-setup-on-a-fresh-mac.md`
