#!/bin/sh
# Tests check-appkit-boundary.sh against small generated trees.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-appkit-boundary.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

make_tree() {
    rm -rf "$work/tree"
    for package in FileSystemCore FileMetadata FileOperations TestSupport BrowserUI; do
        mkdir -p "$work/tree/Packages/$package/Sources/$package" "$work/tree/Packages/$package/Tests/${package}Tests"
        echo 'let package = Package(name: "x")' > "$work/tree/Packages/$package/Package.swift"
        echo 'import Foundation' > "$work/tree/Packages/$package/Sources/$package/File.swift"
    done
    echo 'import AppKit' > "$work/tree/Packages/BrowserUI/Sources/BrowserUI/View.swift"
}

expect() { # expect pass|fail NAME
    if CAIRN_ROOT="$work/tree" "$check" >/dev/null 2>&1; then actual=pass; else actual=fail; fi
    if [ "$actual" = "$1" ]; then echo "ok: $2"; else echo "NOT OK: $2 (expected $1)"; failed=1; fi
}

make_tree
expect pass "allows AppKit in BrowserUI only"

make_tree; echo 'import AppKit' >> "$work/tree/Packages/FileSystemCore/Sources/FileSystemCore/File.swift"
expect fail "rejects import AppKit in a core package"

make_tree; echo '  @preconcurrency import SwiftUI' >> "$work/tree/Packages/FileMetadata/Sources/FileMetadata/File.swift"
expect fail "rejects an attributed SwiftUI import"

make_tree; echo 'import class AppKit.NSImage' >> "$work/tree/Packages/FileOperations/Sources/FileOperations/File.swift"
expect fail "rejects a scoped AppKit import"

make_tree; echo 'import Cocoa' > "$work/tree/Packages/TestSupport/Tests/TestSupportTests/T.swift"
expect fail "rejects Cocoa in a core package's tests"

make_tree; echo '// never import AppKit here' >> "$work/tree/Packages/FileSystemCore/Sources/FileSystemCore/File.swift"
expect pass "ignores a comment that mentions AppKit"

make_tree; echo '.package(path: "../BrowserUI")' >> "$work/tree/Packages/FileOperations/Package.swift"
expect fail "rejects a core manifest that depends on BrowserUI"

make_tree; rm -rf "$work/tree/Packages/FileMetadata"
expect fail "rejects a missing core package"

exit "$failed"
