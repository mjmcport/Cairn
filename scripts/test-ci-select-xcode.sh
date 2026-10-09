#!/bin/sh
# Tests ci-select-xcode.sh against fake Applications folders.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
pinned="$(cat "$here/../.xcode-version")"
major="${pinned%%.*}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

expect() { # expect NAME EXPECTED_APP [OPTION] -- uses $work/apps
    actual="$(CAIRN_APPLICATIONS="$work/apps" "$here/ci-select-xcode.sh" ${3:-} 2>/dev/null)"
    if [ "$actual" = "DEVELOPER_DIR=$work/apps/$2/Contents/Developer" ]; then
        echo "ok: $1"
    else
        echo "NOT OK: $1 (got $actual)"; failed=1
    fi
}

expect_refusal() { # expect_refusal NAME -- strict mode must exit 1, print nothing, and say why
    actual="$(CAIRN_APPLICATIONS="$work/apps" "$here/ci-select-xcode.sh" --strict 2>"$work/stderr")"
    status=$?
    if [ "$status" -ne 1 ]; then
        echo "NOT OK: $1 (exit $status, expected 1)"; failed=1
    elif [ -n "$actual" ]; then
        echo "NOT OK: $1 (printed $actual)"; failed=1
    elif ! grep -q "No Xcode $major" "$work/stderr"; then
        echo "NOT OK: $1 (no message naming Xcode $major)"; failed=1
    else
        echo "ok: $1"
    fi
}

fresh() { rm -rf "$work/apps"; mkdir -p "$work/apps"; for app in "$@"; do mkdir -p "$work/apps/$app"; done; }

fresh "Xcode_$pinned.app" "Xcode_$major.9.app" Xcode.app
expect "prefers the pinned version" "Xcode_$pinned.app"

fresh "Xcode_$major.0.app" "Xcode_$major.2.app" "Xcode_$major.10.app" "Xcode_$((major - 1)).4.app" Xcode.app
expect "falls back to the newest of the same major version" "Xcode_$major.10.app"

fresh "Xcode_$((major - 1)).4.app" Xcode.app
expect "falls back to the default Xcode" "Xcode.app"
expect_refusal "strict mode refuses the default Xcode when no Xcode $major is installed"

fresh "Xcode_$pinned.app" "Xcode_$major.9.app" Xcode.app
expect "strict mode prefers the pinned version" "Xcode_$pinned.app" --strict

fresh "Xcode_$major.0.1.app" "Xcode_$major.3.app" "Xcode_$((major - 10)).4.app" Xcode.app
expect "strict mode takes the newest of the same major version" "Xcode_$major.3.app" --strict

fresh "Xcode_$pinned.app"
if CAIRN_APPLICATIONS="$work/apps" "$here/ci-select-xcode.sh" --lenient >/dev/null 2>&1; then
    echo "NOT OK: rejects an option it does not know"; failed=1
else
    echo "ok: rejects an option it does not know"
fi

exit "$failed"
