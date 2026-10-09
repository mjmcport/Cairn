#!/bin/sh
# Tests check-governance.sh: it must pass on this repository and fail when a
# required file or statement is removed from a copy.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
check="$here/check-governance.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

copy_repo() {
    rm -rf "$work/tree"
    mkdir -p "$work/tree"
    (cd "$repo" && tar -cf - --exclude .git .) | (cd "$work/tree" && tar -xf -)
}

expect_pass() {
    if CAIRN_ROOT="$2" "$check" >/dev/null 2>&1; then
        echo "ok: $1"
    else
        echo "NOT OK: $1 (expected pass)"; failed=1
    fi
}

expect_fail() {
    if CAIRN_ROOT="$work/tree" "$check" >/dev/null 2>&1; then
        echo "NOT OK: $1 (expected failure)"; failed=1
    else
        echo "ok: $1"
    fi
}

expect_pass "passes on the repository" "$repo"

copy_repo; rm "$work/tree/SECURITY.md"
expect_fail "fails when SECURITY.md is missing"

copy_repo; : > "$work/tree/CODE_OF_CONDUCT.md"
expect_fail "fails when CODE_OF_CONDUCT.md is empty"

copy_repo; sed -i '' 's/Matthew McGuire/Someone Else/' "$work/tree/LICENSE"
expect_fail "fails when the copyright line changes"

copy_repo; sed -i '' '/telemetry/d' "$work/tree/README.md"
expect_fail "fails when the README drops the no-telemetry promise"

copy_repo; sed -i '' '/GPL/d' "$work/tree/CONTRIBUTING.md"
expect_fail "fails when CONTRIBUTING drops the clean-room rule"

copy_repo; sed -i '' '/^\*\.xcodeproj$/d' "$work/tree/.gitignore"
expect_fail "fails when .gitignore stops ignoring the generated project"

exit "$failed"
