# 5. Distribution outside the App Store

- Status: Accepted
- Date: 2026-10-09

## Context

A file manager needs to read and change files anywhere the user can, run command-line tools, request Full Disk Access and, later, use a privileged helper for root operations. The App Store requires the sandbox, which forbids most of that; the App Store edition of QSpace cannot use administrator privileges or run command-line apps.

## Decision

Distribute Cairn outside the App Store: signed with a Developer ID, notarized, with the hardened runtime on and the sandbox off. Updates come through Sparkle 2 with EdDSA-signed appcasts. Phase 0 builds are signed ad hoc ("sign to run locally") and are not distributed.

## Consequences

- Cairn can do what a file manager must do, without sandbox workarounds.
- The Apple Developer Program membership is needed by the end of Phase 1.
- The project carries its own release pipeline: signing, notarization, a disk image and the update feed.
- Without the sandbox, security depends on the code. The hardened runtime stays on, there is no networking beyond the update check, and the root helper gets a security review before it ships.
- Users install by download rather than from the App Store.

## Alternatives considered

- **App Store only.** Not viable for the feature set.
- **Both editions.** Doubles the testing for a reduced edition; could be revisited after Phase 3.
