# 2. XcodeGen for the project file

- Status: Accepted
- Date: 2026-10-09

## Context

An `.xcodeproj` is a generated-looking file that conflicts on almost every merge and hides build-setting changes in noise. The project also needs its build settings (arm64 only, macOS 15, hardened runtime, no sandbox) to be reviewable and testable.

## Decision

Describe the project in `project.yml` and generate `Cairn.xcodeproj` with XcodeGen (MIT). Do not commit the generated project. Wrap generation and every build task in a `Makefile`.

## Consequences

- Build settings are a short, readable file. `scripts/check-project-spec.sh` checks the generated settings against the decisions.
- Contributors need XcodeGen; `make bootstrap` installs it.
- After pulling, run `make generate` before opening Xcode. Settings changed in Xcode's interface are lost unless copied into `project.yml`.
- Xcode's own performance baselines live inside the project file, so the performance baseline is kept as JSON instead.

## Alternatives considered

- **Commit the `.xcodeproj`.** Simplest to start, worst to merge.
- **Swift Package Manager only.** It cannot yet describe a signed, notarized Mac app bundle with UI tests.
- **Tuist.** More capable and more to learn; XcodeGen does what this project needs.
