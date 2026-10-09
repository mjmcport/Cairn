# docs: Phase 0 step 11, architecture records

Date: 2026-10-09

Write down how the code is organized and why, while the reasons are fresh, so a contributor or a later session can change the structure knowingly.

## Acceptance criteria

- [x] `ARCHITECTURE.md`: the layers and the AppKit boundary, what each module owns and may import, how a folder gets on screen, the rules the code enforces and what enforces each, the test kinds, the build
- [x] Six decision records in `docs/adr`, each with status, date, context, decision, consequences and alternatives:
  1. AppKit for the interface
  2. XcodeGen for the project file
  3. MIT license with clean-room rules
  4. Minimum macOS 15
  5. Distribution outside the App Store
  6. No telemetry
- [x] `ARCHITECTURE.md` links every record; the README links both

## Tests

- [x] `scripts/check-governance.sh` requires `ARCHITECTURE.md` and the six records, requires each record to have a status, a Decision section and a Consequences section, and requires `ARCHITECTURE.md` to link each record
- [x] `scripts/test-check-governance.sh` proves the check fails for a missing record, a record without a Decision section and an unlinked record

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 11
