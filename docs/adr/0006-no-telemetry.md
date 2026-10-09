# 6. No telemetry

- Status: Accepted
- Date: 2026-10-09

## Context

A file manager sees the names and locations of everything on a Mac. Users of other file managers have objected to privacy policies and data collection. Trust is a quality bar for Cairn, not a feature.

## Decision

Cairn collects no telemetry and no analytics, and has no networking code outside the update checker.

- Diagnostic reports from MetricKit are saved as files in `~/Library/Application Support/Cairn/Diagnostics` and go nowhere unless the user shares one.
- Logs use `os.Logger`, where paths and file names are redacted by default. No message marks one public.
- No feature is locked behind a paywall.

## Consequences

- There are no usage numbers. Priorities come from issues, the parity research and the maintainer's own daily use.
- Crashes are learned about only when a user sends a report, so the reports must be easy to find and share.
- `scripts/check-no-network.sh` fails the build if a networking API appears outside the allowed folder.
- The update check, when it ships, is the one network request, and the README says so.

## Alternatives considered

- **Opt-in analytics.** Still requires networking code, a server and a policy, and still costs trust.
- **Automatic crash reporting.** Useful, but a stack trace from a file manager can contain file names.
