#!/bin/sh
# Tests check-main-thread-guard.sh and check-no-network.sh against small
# generated trees.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0
source_dir="$work/tree/Packages/FileSystemCore/Sources/FileSystemCore"

make_tree() {
    rm -rf "$work/tree"
    mkdir -p "$source_dir" "$work/tree/App" "$work/tree/Packages/FileSystemCore/Tests/FileSystemCoreTests"
    echo 'import Foundation' > "$source_dir/Plain.swift"
    echo 'import AppKit' > "$work/tree/App/AppDelegate.swift"
}

expect() { # expect SCRIPT pass|fail NAME
    if CAIRN_ROOT="$work/tree" "$here/$1" >/dev/null 2>&1; then actual=pass; else actual=fail; fi
    if [ "$actual" = "$2" ]; then echo "ok: $3"; else echo "NOT OK: $3 (expected $2)"; failed=1; fi
}

guard=check-main-thread-guard.sh
make_tree
expect $guard pass "guard: allows a file with no file-system calls"

make_tree; echo 'let x = try FileManager.default.contentsOfDirectory(atPath: p)' > "$source_dir/Bad.swift"
expect $guard fail "guard: rejects FileManager without a guard"

make_tree; printf 'MainThreadGuard.assertOffMainThread()\nlet x = try FileManager.default.contentsOfDirectory(atPath: p)\n' > "$source_dir/Good.swift"
expect $guard pass "guard: allows FileManager with a guard"

make_tree; echo 'let v = try url.resourceValues(forKeys: keys)' > "$source_dir/Bad.swift"
expect $guard fail "guard: rejects resourceValues without a guard"

make_tree; echo '  guard lstat(path, &info) == 0 else { return }' > "$source_dir/Bad.swift"
expect $guard fail "guard: rejects a POSIX call without a guard"

make_tree; echo 'let d = try Data(contentsOf: url)' > "$source_dir/Bad.swift"
expect $guard fail "guard: rejects Data(contentsOf:) without a guard"

make_tree; echo 'public init(url: URL, resourceValues values: URLResourceValues) {}' > "$source_dir/Fine.swift"
expect $guard pass "guard: ignores a parameter named resourceValues"

make_tree; echo 'let x = try FileManager.default.contentsOfDirectory(atPath: p)' > "$work/tree/Packages/FileSystemCore/Tests/FileSystemCoreTests/T.swift"
expect $guard pass "guard: ignores test targets"

make_tree; printf '  case rename(item: URL, newName: String)\n  // call stat( here later\n' > "$source_dir/Fine.swift"
expect $guard pass "guard: ignores an enum case and a comment that share a call's name"

network=check-no-network.sh
make_tree
expect $network pass "network: allows code with no networking"

make_tree; echo 'let task = URLSession.shared.dataTask(with: url)' > "$source_dir/Bad.swift"
expect $network fail "network: rejects URLSession in a package"

make_tree; echo 'import Network' >> "$work/tree/App/AppDelegate.swift"
expect $network fail "network: rejects import Network in the app"

make_tree; echo 'let view = WKWebView()' >> "$work/tree/App/AppDelegate.swift"
expect $network fail "network: rejects a web view"

make_tree; echo 'let s = URLSession.shared' > "$work/tree/Packages/FileSystemCore/Tests/FileSystemCoreTests/T.swift"
expect $network pass "network: ignores test targets"

accessibility=check-accessibility.sh
ui_dir="$work/tree/Packages/BrowserUI/Sources/BrowserUI"
make_ui_tree() {
    make_tree
    mkdir -p "$ui_dir"
    echo 'view.setAccessibilityIdentifier(element.identifier)' > "$ui_dir/Accessibility.swift"
    echo 'tableView.apply(.fileList)' > "$ui_dir/View.swift"
}

make_ui_tree
expect $accessibility pass "accessibility: allows the helper file and apply(_:)"

make_ui_tree; echo 'button.setAccessibilityIdentifier("ok")' >> "$ui_dir/View.swift"
expect $accessibility fail "accessibility: rejects a direct identifier in BrowserUI"

make_ui_tree; echo 'button.setAccessibilityLabel("OK")' >> "$work/tree/App/AppDelegate.swift"
expect $accessibility fail "accessibility: rejects a direct label in the app"

make_ui_tree; echo 'window.identifier = NSUserInterfaceItemIdentifier("main")' >> "$work/tree/App/AppDelegate.swift"
expect $accessibility fail "accessibility: rejects a literal view identifier"

make_ui_tree; echo '// never call setAccessibilityLabel( directly' >> "$ui_dir/View.swift"
expect $accessibility pass "accessibility: ignores a comment"

exit "$failed"
