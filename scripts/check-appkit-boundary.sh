#!/bin/sh
# Enforces the AppKit boundary: the core packages must not import a UI
# framework, and their manifests must not depend on BrowserUI. Only BrowserUI
# and the app target may use AppKit or SwiftUI.
#
# Set CAIRN_ROOT to check a different tree (used by the script's own test).

root="${CAIRN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
core_packages="FileSystemCore FileMetadata FileOperations TestSupport"
ui_packages="BrowserUI"
ui_imports='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|internal|package|private|fileprivate)[[:space:]]+)?import[[:space:]]+((struct|class|enum|protocol|typealias|func|let|var)[[:space:]]+)?(AppKit|SwiftUI|Cocoa|UIKit)([.[:space:]]|$)'
failures=0

for package in $core_packages; do
    directory="$root/Packages/$package"
    if [ ! -d "$directory" ]; then
        echo "FAIL: Packages/$package is missing" >&2
        failures=$((failures + 1))
        continue
    fi

    matches="$(grep -rnE --include='*.swift' "$ui_imports" "$directory/Sources" "$directory/Tests" 2>/dev/null)"
    if [ -n "$matches" ]; then
        echo "FAIL: $package imports a UI framework:" >&2
        echo "$matches" | sed "s|^$root/|    |" >&2
        failures=$((failures + 1))
    fi

    if grep -q 'BrowserUI' "$directory/Package.swift"; then
        echo "FAIL: $package's manifest depends on BrowserUI" >&2
        failures=$((failures + 1))
    fi
done

# A package named in neither list would be built and tested but never checked.
for directory in "$root"/Packages/*/; do
    [ -d "$directory" ] || continue
    package="$(basename "$directory")"
    case " $core_packages $ui_packages " in
        *" $package "*) ;;
        *)
            echo "FAIL: Packages/$package is in neither core_packages nor ui_packages in $(basename "$0")" >&2
            failures=$((failures + 1))
            ;;
    esac
done

if [ "$failures" -gt 0 ]; then
    echo "$failures AppKit-boundary check(s) failed" >&2
    exit 1
fi
echo "AppKit-boundary checks passed"
