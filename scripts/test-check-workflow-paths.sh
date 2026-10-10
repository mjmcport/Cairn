#!/bin/sh
# Tests check-workflow-paths.py: it must pass on this repository's workflows
# and fail when CI ignores a path the Documents workflow does not list.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
work="$base/with space"
mkdir -p "$work"
tool="$here/check-workflow-paths.py"
failed=0

expect() { # expect pass|fail NAME [TEXT]
    output="$(python3 "$tool" "$work/ci.yml" "$work/documents.yml" 2>&1)"
    if [ $? -eq 0 ]; then actual=pass; else actual=fail; fi
    case "$output" in *"${3:-}"*) found=1 ;; *) found=0 ;; esac
    if [ "$actual" = "$1" ] && [ "$found" -eq 1 ]; then echo "ok: $2"
    else echo "NOT OK: $2 (expected $1, got $actual: $output)"; failed=1; fi
}

fresh() {
    cp "$repo/.github/workflows/ci.yml" "$work/ci.yml"
    cp "$repo/.github/workflows/documents.yml" "$work/documents.yml"
}

fresh
expect pass "the repository's two workflows agree"

fresh
sed 's|      - "docs/\*\*"|      - "docs/**"\
      - "notes/**"|' "$work/ci.yml" > "$work/ci.new" && mv "$work/ci.new" "$work/ci.yml"
expect fail "a path CI ignores and Documents does not list" "notes/**"

fresh
grep -v '"plans/\*\*"' "$work/documents.yml" > "$work/documents.new" && mv "$work/documents.new" "$work/documents.yml"
expect fail "a path removed from the Documents workflow" "plans/**"

fresh
grep -v 'paths-ignore' "$work/ci.yml" > "$work/ci.new" && mv "$work/ci.new" "$work/ci.yml"
expect fail "a CI workflow that ignores nothing" "should ignore paths"

fresh
rm "$work/documents.yml"
expect fail "a missing Documents workflow" "FAIL"

exit "$failed"
