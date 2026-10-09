# ci: Phase 0 step 12, build artifact

Date: 2026-10-09

Give every commit on `main` a downloadable build, so a change can be tried without a development setup and a regression can be traced to the build that introduced it.

## Acceptance criteria

- [x] `make package` builds the Release app, zips it as `build/package/Cairn-<version>-<commit>-unsigned.zip` and checks the zip
- [x] CI packages and uploads the build for every push to `main`, kept for 30 days
- [x] The build has no Developer ID and is not notarized; signing waits for Phase 1

## Tests

- [x] `scripts/check-package.sh` unzips the package and checks: bundle ID, minimum system version 15.0, arm64 only, ad hoc signature that verifies, hardened runtime on, no team identifier, no sandbox entitlement, and that the app is still running three seconds after launch
- [x] `scripts/test-check-package.sh`: the check rejects a missing file, a non-zip, a zip without `Cairn.app` and a fake unsigned bundle
- [ ] CI on this commit uploads the artifact (confirmed after the push; see the session report)

## Design notes

- "Unsigned" means no Developer ID. The build is signed ad hoc, because an Apple Silicon Mac will not run a binary with no signature at all. Gatekeeper refuses it on another Mac unless the user overrides that, and the file name says `unsigned` so nobody mistakes it for a release.
- Packaging runs only on pushes to `main`, not on pull requests, to save runner minutes.
- `ditto` makes the zip, which keeps the bundle's permissions and symlinks intact.

## Phase 0 exit gate

| Gate | Status |
| --- | --- |
| A clean clone builds and passes all tests with one command on an Apple Silicon Mac | Met: `make`, proved by `make clean-clone` |
| CI is green on main and blocks a failing pull request | Half met: CI is green (after the accessibility-audit fix that follows step 12) and turns a failing pull request red. Blocking needs branch protection, which GitHub's free plan refuses on a private repository |
| The app lists a folder and navigates into subfolders, covered by an end-to-end test | Met: `UITests/BrowsingTests.swift` |
| Performance baselines are committed for 10,000- and 100,000-item folders | Met: `docs/performance/baseline.json` |
| The six decision records are merged | Met: `docs/adr` |

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 12 and the exit gate
