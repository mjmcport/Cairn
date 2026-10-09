# 3. MIT license with clean-room rules

- Status: Accepted
- Date: 2026-10-09

## Context

Cairn is meant to be open and reusable. Several existing Mac file managers are closed source, and Nimble Commander is GPL-3. Code derived from either would make the MIT license untrue.

## Decision

License Cairn under MIT. Enforce clean-room rules, stated in `CONTRIBUTING.md`:

- No code copied, translated or adapted from GPL, LGPL or AGPL projects. Nimble Commander's source is off limits, including as a reference.
- No code or assets from closed-source apps, and no reverse engineering of them.
- Studying behavior as a user, and reading Apple's documentation and headers, is allowed.
- Dependencies must be MIT, BSD, Apache-2.0 or zlib, and each needs an issue first.

## Consequences

- Anyone can use, fork or embed Cairn, including commercially.
- Some features take longer because a working GPL implementation cannot be consulted.
- Each planned dependency (Sparkle, libarchive, a terminal view) needs its license, and the licenses of what it bundles, checked before adoption.
- The pull-request template asks every contributor to confirm the rule.

## Alternatives considered

- **GPL-3.** Would allow learning from Nimble Commander, but restricts reuse and was not wanted.
- **MIT without written rules.** The license alone does not stop a well-meant paste from a GPL project.
