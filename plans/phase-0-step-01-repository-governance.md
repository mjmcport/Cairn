# docs: Phase 0 step 1, repository and governance

Date: 2026-10-09

Give the repo the files every later step and every contributor relies on: what Cairn is, the licence, the contribution rules, and the settled decisions that each Claude Code session should start from.

## Acceptance criteria

- [x] `README.md`: what Cairn is, status (Phase 0), macOS 15+, Apple Silicon only, build steps, privacy statement
- [x] `LICENSE`: MIT, `Copyright (c) 2026 Matthew McGuire`
- [x] `CONTRIBUTING.md`: clean-room rule (no GPL or closed-source code; Nimble Commander is GPL-3), tests required with every change, one commit per step, dependency licences limited to MIT, BSD, Apache-2.0 and zlib
- [x] `CODE_OF_CONDUCT.md` and `SECURITY.md`
- [x] `.github/ISSUE_TEMPLATE/` (bug report, feature request, config) and `.github/PULL_REQUEST_TEMPLATE.md`
- [x] `.gitignore`: Xcode, SwiftPM, generated `.xcodeproj`, DerivedData, `.DS_Store`
- [x] `CLAUDE.md`: decisions table from the kickoff, the per-step loop, recorded toolchain versions
- [x] `scripts/check-governance.sh` passes and fails when a required file or statement is missing

## Context

- The repo has one commit from GitHub's template: a stub README, an MIT licence naming `mjmcport`, and GitHub's Swift `.gitignore`, which leaves `*.xcodeproj` commented out.
- The minimum macOS is 15, raised from the plan's 14.
- The build steps in the README describe `make` tasks that arrive in step 2; the README says so.
- The repo is private, so GitHub's private vulnerability reporting is unavailable. `SECURITY.md` names a direct contact until the repo goes public.

## Test

Docs-only step, so the test is a shell check rather than a Swift test:

```sh
# scripts/check-governance.sh
# 1. every required file exists and is non-empty
# 2. LICENSE has the MIT title and the copyright line
# 3. README states macOS 15, Apple Silicon and the no-telemetry promise
# 4. CONTRIBUTING states the clean-room and tests-required rules
# 5. .gitignore ignores *.xcodeproj, DerivedData and .DS_Store
```

Step 9 (CI) runs this script on every push.

## References

- `../cairn-phase-0-kickoff.md` (decisions and setup order)
- Claude Doc "Mac file manager implementation plan", Phase 0 step 1 and quality bar 10
