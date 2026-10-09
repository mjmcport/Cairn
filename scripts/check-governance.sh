#!/bin/sh
# Checks that the governance files exist and still carry the statements the
# project depends on. Run from anywhere; reports every failure, then exits
# non-zero if there was one.
#
# Set CAIRN_ROOT to check a different tree (used by the script's own test).

root="${CAIRN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
failures=0

fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

require_file() {
    [ -s "$root/$1" ] || fail "$1 is missing or empty"
}

# require_text FILE PATTERN DESCRIPTION
require_text() {
    [ -f "$root/$1" ] || return 0
    grep -Eqi -- "$2" "$root/$1" || fail "$1 does not state: $3"
}

# require_line FILE LINE DESCRIPTION (exact, whole-line match)
require_line() {
    [ -f "$root/$1" ] || return 0
    grep -Fxq -- "$2" "$root/$1" || fail "$1 does not have the line: $3"
}

for file in \
    README.md \
    LICENSE \
    CONTRIBUTING.md \
    CODE_OF_CONDUCT.md \
    SECURITY.md \
    CLAUDE.md \
    .gitignore \
    .github/PULL_REQUEST_TEMPLATE.md \
    .github/ISSUE_TEMPLATE/bug_report.yml \
    .github/ISSUE_TEMPLATE/feature_request.yml \
    .github/ISSUE_TEMPLATE/config.yml \
    ARCHITECTURE.md \
    docs/adr/0001-appkit-for-the-interface.md \
    docs/adr/0002-xcodegen-for-the-project-file.md \
    docs/adr/0003-mit-license-with-clean-room-rules.md \
    docs/adr/0004-minimum-macos-15.md \
    docs/adr/0005-distribution-outside-the-app-store.md \
    docs/adr/0006-no-telemetry.md
do
    require_file "$file"
done

require_line LICENSE "MIT License" "MIT License"
require_line LICENSE "Copyright (c) 2026 Matthew McGuire" "Copyright (c) 2026 Matthew McGuire"

require_text README.md "macOS.*15" "minimum macOS 15"
require_text README.md "Apple Silicon" "Apple Silicon only"
require_text README.md "Phase 0" "project status"
require_text README.md "no telemetry" "no telemetry"
require_text README.md "stay on your Mac" "crash reports stay local"

require_text CONTRIBUTING.md "GPL" "the clean-room rule"
require_text CONTRIBUTING.md "Nimble Commander is GPL-3" "Nimble Commander is GPL-3"
require_text CONTRIBUTING.md "ships with its tests" "tests required with every change"
require_text CONTRIBUTING.md "One commit per step" "one commit per step"
require_text CONTRIBUTING.md "MIT, BSD.*Apache-2\.0 and zlib" "allowed dependency licences"

require_text CLAUDE.md "Minimum macOS \| \*\*15 Sequoia\*\*" "minimum macOS decision"
require_text CLAUDE.md "com\.mjmcport\.cairn" "bundle ID decision"
require_text CLAUDE.md "wait for CI with .gh run watch." "wait for CI after each push"
require_text CLAUDE.md "Push at milestones, not after every commit" "push at milestones"
require_text CLAUDE.md "open a pull request\. Merge only when CI is green" "the pull-request rule"
require_text CLAUDE.md "CI runner is macOS 26.*development Mac is macOS 27.*minimum supported is macOS 15" \
    "the three macOS versions"

for record in "$root"/docs/adr/0*.md; do
    name="docs/adr/$(basename "$record")"
    require_text "$name" "^- Status: (Proposed|Accepted|Superseded)" "a status"
    require_text "$name" "^## Decision" "a Decision section"
    require_text "$name" "^## Consequences" "a Consequences section"
    require_text ARCHITECTURE.md "$name" "a link to $name"
done

require_line .gitignore "*.xcodeproj" "*.xcodeproj"
require_line .gitignore "DerivedData/" "DerivedData/"
require_line .gitignore ".DS_Store" ".DS_Store"

if [ "$failures" -gt 0 ]; then
    echo "$failures governance check(s) failed" >&2
    exit 1
fi
echo "Governance checks passed"
