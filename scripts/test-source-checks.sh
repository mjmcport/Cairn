#!/bin/sh
# Tests check-main-thread-guard.sh, check-no-network.sh and
# check-accessibility.sh against small generated trees.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0
root="$work/tree"
source_dir="$work/tree/Packages/FileSystemCore/Sources/FileSystemCore"

make_tree() {
    rm -rf "$work/tree"
    mkdir -p "$source_dir" "$work/tree/App" "$work/tree/Packages/FileSystemCore/Tests/FileSystemCoreTests"
    echo 'import Foundation' > "$source_dir/Plain.swift"
    echo 'import AppKit' > "$work/tree/App/AppDelegate.swift"
}

expect() { # expect SCRIPT pass|fail NAME
    if CAIRN_ROOT="$root" "$here/$1" >/dev/null 2>&1; then actual=pass; else actual=fail; fi
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

make_tree; echo '    let stream = FSEventStreamCreate(nil, callback, &context, paths, since, 0.3, flags)' > "$source_dir/Bad.swift"
expect $guard fail "guard: rejects FSEventStreamCreate without a guard"

make_tree; printf 'MainThreadGuard.assertOffMainThread()\n    let stream = FSEventStreamCreate(nil, callback, &context, paths, since, 0.3, flags)\n' > "$source_dir/Good.swift"
expect $guard pass "guard: allows FSEventStreamCreate with a guard"

make_tree; echo '    guard let path = realpath(spelled, nil) else { return spelled }' > "$source_dir/Bad.swift"
expect $guard fail "guard: rejects realpath without a guard"

make_tree; printf 'MainThreadGuard.assertOffMainThread()\n    guard let path = realpath(spelled, nil) else { return spelled }\n' > "$source_dir/Good.swift"
expect $guard pass "guard: allows realpath with a guard"

make_tree; echo 'public init(url: URL, resourceValues values: URLResourceValues) {}' > "$source_dir/Fine.swift"
expect $guard pass "guard: ignores a parameter named resourceValues"

make_tree; echo 'let x = try FileManager.default.contentsOfDirectory(atPath: p)' > "$work/tree/Packages/FileSystemCore/Tests/FileSystemCoreTests/T.swift"
expect $guard pass "guard: ignores test targets"

make_tree; printf '  case rename(item: URL, newName: String)\n  // call stat( here later\n' > "$source_dir/Fine.swift"
expect $guard pass "guard: ignores an enum case and a comment that share a call's name"

make_tree; mkdir -p "$work/tree/Packages/NewPackage/Sources/NewPackage"
echo 'let d = try Data(contentsOf: url)' > "$work/tree/Packages/NewPackage/Sources/NewPackage/Bad.swift"
expect $guard fail "guard: checks a package it has never heard of"

make_tree; mkdir -p "$work/tree/Packages/TestSupport/Sources/TestSupport"
echo 'let d = try Data(contentsOf: url)' > "$work/tree/Packages/TestSupport/Sources/TestSupport/Fixture.swift"
expect $guard pass "guard: exempts TestSupport"

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

toolbar_literal='let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("go-back"))'
make_ui_tree; echo "$toolbar_literal" >> "$ui_dir/View.swift"
expect $accessibility fail "accessibility: rejects a toolbar item built outside the helper file"

make_ui_tree; echo 'static let back = NSToolbarItem.Identifier("go-back")' >> "$work/tree/App/AppDelegate.swift"
expect $accessibility fail "accessibility: rejects a literal toolbar item identifier in the app"

make_ui_tree; echo "$toolbar_literal" >> "$ui_dir/Accessibility.swift"
echo 'let item = NSToolbarItem(.backButton, symbolName: "chevron.left")' >> "$ui_dir/View.swift"
expect $accessibility pass "accessibility: allows a toolbar item built in the helper file"

# A checkout under a folder whose name has a space is checked like any other.
move_tree_under_a_space() {
    rm -rf "$work/My Projects"
    mkdir -p "$work/My Projects"
    mv "$work/tree" "$work/My Projects/tree"
    root="$work/My Projects/tree"
}

make_ui_tree; move_tree_under_a_space
expect $guard pass "space in path: guard allows a clean tree"
expect $network pass "space in path: network allows a clean tree"
expect $accessibility pass "space in path: accessibility allows a clean tree"

make_ui_tree
echo 'let x = try FileManager.default.contentsOfDirectory(atPath: p)' > "$source_dir/Bad.swift"
echo 'let task = URLSession.shared.dataTask(with: url)' > "$source_dir/Worse.swift"
echo 'button.setAccessibilityLabel("OK")' >> "$work/tree/App/AppDelegate.swift"
move_tree_under_a_space
expect $guard fail "space in path: guard rejects FileManager without a guard"
expect $network fail "space in path: network rejects URLSession"
expect $accessibility fail "space in path: accessibility rejects a direct label"

make_ui_tree; echo "$toolbar_literal" >> "$ui_dir/View.swift"
move_tree_under_a_space
expect $accessibility fail "space in path: accessibility rejects a toolbar item built outside the helper file"

make_tree; echo '    let stream = FSEventStreamCreate(nil, callback, &context, paths, since, 0.3, flags)' > "$source_dir/Bad.swift"
move_tree_under_a_space
expect $guard fail "space in path: guard rejects FSEventStreamCreate without a guard"

make_tree; echo '    guard let path = realpath(spelled, nil) else { return spelled }' > "$source_dir/Bad.swift"
move_tree_under_a_space
expect $guard fail "space in path: guard rejects realpath without a guard"
root="$work/tree"

exit "$failed"
