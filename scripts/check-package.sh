#!/bin/sh
# Checks a packaged build: the zip unpacks to a Cairn.app that is arm64 only,
# targets macOS 15.0, carries the right bundle ID, has the hardened runtime
# on and the sandbox off, is signed ad hoc with a valid signature, and
# launches.
#
# Usage: check-package.sh ZIP

set -u
zip="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
expect() { # expect DESCRIPTION ACTUAL EXPECTED
    [ "$2" = "$3" ] || fail "$1 is '$2', expected '$3'"
}

[ -f "$zip" ] || { echo "FAIL: no package at $zip" >&2; exit 1; }
ditto -x -k "$zip" "$work" || { echo "FAIL: the package does not unzip" >&2; exit 1; }

app="$work/Cairn.app"
binary="$app/Contents/MacOS/Cairn"
plist="$app/Contents/Info.plist"
[ -x "$binary" ] || { echo "FAIL: the package has no Cairn.app/Contents/MacOS/Cairn" >&2; exit 1; }

expect "bundle ID" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" com.mjmcport.cairn
expect "minimum system version" "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" 15.0
expect "architectures" "$(lipo -archs "$binary")" arm64

signature="$(codesign --display --verbose=4 "$app" 2>&1)"
echo "$signature" | grep -q '^Signature=adhoc' || fail "the build is not signed ad hoc"
echo "$signature" | grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\(.*runtime.*\)' \
    || fail "the hardened runtime is not on"
echo "$signature" | grep -q '^TeamIdentifier=not set' || fail "the build carries a team identifier"
codesign --verify --deep --strict "$app" 2>/dev/null || fail "the signature does not verify"

entitlements="$(codesign --display --entitlements - "$app" 2>/dev/null)"
if echo "$entitlements" | grep -q 'com.apple.security.app-sandbox'; then
    fail "the build is sandboxed"
fi

# Launch it on an empty folder and make sure it is still running a moment later.
mkdir "$work/folder"
"$binary" -OpenFolder "$work/folder" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
pid=$!
sleep 3
if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
else
    fail "the packaged app exited within 3 seconds of launch"
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures package check(s) failed" >&2
    exit 1
fi
echo "Package checks passed: $(basename "$zip"), $(du -h "$zip" | cut -f1 | tr -d ' ')"
