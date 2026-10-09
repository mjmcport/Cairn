#!/bin/sh
# Tests check-package.sh's rejections. The passing case runs in `make package`,
# which needs a Release build.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

expect_fail() { # expect_fail NAME ZIP
    if "$here/check-package.sh" "$2" >/dev/null 2>&1; then
        echo "NOT OK: $1 (expected failure)"; failed=1
    else
        echo "ok: $1"
    fi
}

expect_fail "rejects a missing package" "$work/missing.zip"

echo "not a zip" > "$work/garbage.zip"
expect_fail "rejects a file that is not a zip" "$work/garbage.zip"

mkdir -p "$work/empty/Other.app"
ditto -c -k --keepParent "$work/empty/Other.app" "$work/other.zip"
expect_fail "rejects a zip without Cairn.app" "$work/other.zip"

# A bundle with the right shape but an unsigned, wrong-architecture-free script as its binary.
mkdir -p "$work/fake/Cairn.app/Contents/MacOS"
printf '#!/bin/sh\nsleep 10\n' > "$work/fake/Cairn.app/Contents/MacOS/Cairn"
chmod +x "$work/fake/Cairn.app/Contents/MacOS/Cairn"
cat > "$work/fake/Cairn.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mjmcport.cairn</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
ditto -c -k --keepParent "$work/fake/Cairn.app" "$work/fake.zip"
expect_fail "rejects an unsigned bundle that is not a real build" "$work/fake.zip"

exit "$failed"
