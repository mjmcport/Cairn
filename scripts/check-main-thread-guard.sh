#!/bin/sh
# Enforces quality bar 2 at the source level: a source file in a package that
# calls a file-system API must also call MainThreadGuard.assertOffMainThread().
# This is a per-file check, so review still has to confirm each entry point
# has its own guard; the unit tests prove the guards fire.
#
# Every folder under Packages is checked, so a new package is covered without
# being named here. Only the exemptions are listed.
#
# Set CAIRN_ROOT to check a different tree (used by the script's own test).

root="${CAIRN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
exempt_packages="TestSupport"   # builds fixtures on the test's own thread
file_system_calls='FileManager\.default\.(enumerator|contentsOfDirectory|createDirectory|createFile|removeItem|copyItem|moveItem|trashItem|fileExists|attributesOfItem|setAttributes|createSymbolicLink|linkItem|subpaths)|\.resourceValues\(forKeys|\.setResourceValues\(|Data\(contentsOf:|String\(contentsOf:|\.write\(to:|FileHandle\(for|[^A-Za-z_.](FSEventStreamCreate|realpath|opendir|readdir|lstat|stat|getxattr|setxattr|listxattr|removexattr|copyfile|clonefile|rename|unlink|rmdir|mkdir|symlink|readlink|chmod|chflags|getattrlist|getattrlistbulk|fts_open)\('
failures=0

for directory in "$root"/Packages/*/; do
    package="$(basename "$directory")"
    case " $exempt_packages " in *" $package "*) continue ;; esac
    sources="$root/Packages/$package/Sources"
    [ -d "$sources" ] || continue
    # Split the file list on newlines only, so a path with a space stays one file.
    old_ifs="$IFS"
    IFS='
'
    for file in $(find "$sources" -name '*.swift'); do
        IFS="$old_ifs"
        # Declarations and comments that merely share a name with a call do not count.
        calls="$(grep -En "$file_system_calls" "$file" | grep -Ev '^[0-9]+:[[:space:]]*(case |func |//)')"
        if [ -n "$calls" ] && ! grep -q 'MainThreadGuard\.assertOffMainThread(' "$file"; then
            echo "FAIL: ${file#"$root"/} calls the file system without MainThreadGuard.assertOffMainThread()" >&2
            echo "$calls" | head -3 | sed 's/^/    /' >&2
            failures=$((failures + 1))
        fi
    done
    IFS="$old_ifs"
done

if [ "$failures" -gt 0 ]; then
    echo "$failures main-thread-guard check(s) failed" >&2
    exit 1
fi
echo "Main-thread-guard checks passed"
