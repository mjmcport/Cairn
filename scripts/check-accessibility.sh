#!/bin/sh
# Enforces the accessibility convention (quality bar 9): identifiers and
# labels are set only through AccessibilityElement and its apply helpers, so
# no control gets a test hook without a declared, spoken identity.
#
# Set CAIRN_ROOT to check a different tree (used by the script's own test).

root="${CAIRN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
helper="Packages/BrowserUI/Sources/BrowserUI/Accessibility.swift"
direct_calls='setAccessibilityIdentifier\(|setAccessibilityLabel\(|NSUserInterfaceItemIdentifier\("'
failures=0

# Split the file list on newlines only, so a path with a space stays one file.
old_ifs="$IFS"
IFS='
'
for file in $(find "$root/App" "$root/Packages/BrowserUI/Sources" -name '*.swift' 2>/dev/null); do
    relative="${file#"$root"/}"
    [ "$relative" = "$helper" ] && continue
    matches="$(grep -En "$direct_calls" "$file" | grep -Ev '^[0-9]+:[[:space:]]*//')"
    if [ -n "$matches" ]; then
        echo "FAIL: $relative sets accessibility directly; declare an AccessibilityElement and use apply(_:):" >&2
        echo "$matches" | head -3 | sed 's/^/    /' >&2
        failures=$((failures + 1))
    fi
done
IFS="$old_ifs"

if [ "$failures" -gt 0 ]; then
    echo "$failures accessibility-convention check(s) failed" >&2
    exit 1
fi
echo "Accessibility-convention checks passed"
