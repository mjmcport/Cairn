#!/bin/sh
# Tests ci-select-xcode.sh against fake Applications folders.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
pinned="$(cat "$here/../.xcode-version")"
major="${pinned%%.*}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

expect() { # expect NAME EXPECTED_APP -- uses $work/apps
    actual="$(CAIRN_APPLICATIONS="$work/apps" "$here/ci-select-xcode.sh" 2>/dev/null)"
    if [ "$actual" = "DEVELOPER_DIR=$work/apps/$2/Contents/Developer" ]; then
        echo "ok: $1"
    else
        echo "NOT OK: $1 (got $actual)"; failed=1
    fi
}

fresh() { rm -rf "$work/apps"; mkdir -p "$work/apps"; for app in "$@"; do mkdir -p "$work/apps/$app"; done; }

fresh "Xcode_$pinned.app" "Xcode_$major.9.app" Xcode.app
expect "prefers the pinned version" "Xcode_$pinned.app"

fresh "Xcode_$major.0.app" "Xcode_$major.2.app" "Xcode_$major.10.app" "Xcode_$((major - 1)).4.app" Xcode.app
expect "falls back to the newest of the same major version" "Xcode_$major.10.app"

fresh "Xcode_$((major - 1)).4.app" Xcode.app
expect "falls back to the default Xcode" "Xcode.app"

exit "$failed"
