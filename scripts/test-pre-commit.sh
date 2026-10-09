#!/bin/sh
# Tests the pre-commit hook in a throwaway repository.

set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

# A copy of the tracked and unignored files, as its own repository.
(cd "$repo" && git ls-files -co --exclude-standard -z | xargs -0 tar -cf -) | (cd "$work" && tar -xf -)
cd "$work" || exit 1
git init -q .
git config user.name "Hook Test"
git config user.email "hook-test@example.invalid"
git config core.hooksPath .githooks
git add -A
if git commit -q -m "initial" >/dev/null 2>&1; then
    echo "ok: accepts the repository as it stands"
else
    echo "NOT OK: accepts the repository as it stands"; failed=1
fi

expect_commit() { # expect_commit pass|fail NAME
    if git commit -q -m "test" >/dev/null 2>&1; then actual=pass; else actual=fail; fi
    if [ "$actual" = "$1" ]; then echo "ok: $2"; else echo "NOT OK: $2 (expected $1)"; failed=1; fi
    git reset -q --hard HEAD
    git clean -qfd
}

printf 'struct Tidy {\n  let value = 1\n}\n' > App/Tidy.swift
git add App/Tidy.swift
expect_commit pass "accepts formatted Swift"

printf 'struct   Messy{\n        let value=1\n}\n' > App/Messy.swift
git add App/Messy.swift
expect_commit fail "rejects unformatted Swift"

printf 'struct   Messy{\n        let value=1\n}\n' > App/Messy.swift
git add App/Messy.swift
printf 'struct Messy {\n  let value = 1\n}\n' > App/Messy.swift
expect_commit fail "checks the staged content, not the fixed working copy"

echo "notes" > notes.md
git add notes.md
expect_commit pass "ignores files that are not Swift"

git rm -q SECURITY.md
expect_commit fail "rejects a commit that breaks a governance rule"

exit "$failed"
