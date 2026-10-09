#!/bin/sh
# Checks that the generated project carries the settled build decisions:
# bundle ID, minimum macOS, arm64 only, Swift 6 with strict concurrency,
# hardened runtime on and sandbox off. Run `make generate` first.

root="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
failures=0

for config in Debug Release; do
    settings="$(xcodebuild -project "$root/Cairn.xcodeproj" -target Cairn \
        -configuration "$config" -showBuildSettings 2>&1)" || {
        echo "FAIL: xcodebuild could not read the $config build settings" >&2
        echo "$settings" | tail -5 >&2
        exit 1
    }

    # expect SETTING VALUE
    expect() {
        actual="$(echo "$settings" | awk -F' = ' -v key="$1" '$1 ~ "^ *" key "$" {print $2; exit}')"
        if [ "$actual" != "$2" ]; then
            echo "FAIL ($config): $1 is '$actual', expected '$2'" >&2
            failures=$((failures + 1))
        fi
    }

    expect PRODUCT_BUNDLE_IDENTIFIER com.mjmcport.cairn
    expect MACOSX_DEPLOYMENT_TARGET 15.0
    expect ARCHS arm64
    expect SWIFT_VERSION 6.0
    expect SWIFT_STRICT_CONCURRENCY complete
    expect ENABLE_HARDENED_RUNTIME YES
    expect ENABLE_APP_SANDBOX NO
done

if [ "$failures" -gt 0 ]; then
    echo "$failures project-spec check(s) failed" >&2
    exit 1
fi
echo "Project-spec checks passed"
