#!/bin/sh
# Enforces quality bar 10 at the source level: no networking code in the app
# or its packages. When the update checker arrives in Phase 1, its folder is
# the only one allowed here.
#
# Set CAIRN_ROOT to check a different tree (used by the script's own test).

root="${CAIRN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
allowed_directories=""   # e.g. "App/Updates"
network_apis='URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|^[[:space:]]*import[[:space:]]+(Network|WebKit|CFNetwork|MultipeerConnectivity)|CFSocket|CFStreamCreatePairWithSocket|WKWebView|NSURLConnection|import[[:space:]]+(Sentry|Firebase|Amplitude|Mixpanel)'
failures=0

# Split the file list on newlines only, so a path with a space stays one file.
old_ifs="$IFS"
IFS='
'
for file in $(find "$root/App" "$root/Packages" -name '*.swift' -path '*' ! -path '*/Tests/*' ! -path '*/.build/*' 2>/dev/null); do
    IFS="$old_ifs"
    relative="${file#"$root"/}"
    skip=0
    for allowed in $allowed_directories; do
        case "$relative" in "$allowed"/*) skip=1 ;; esac
    done
    [ "$skip" -eq 1 ] && continue
    if grep -Eq "$network_apis" "$file"; then
        echo "FAIL: $relative uses a networking API:" >&2
        grep -En "$network_apis" "$file" | head -3 | sed 's/^/    /' >&2
        failures=$((failures + 1))
    fi
done
IFS="$old_ifs"

if [ "$failures" -gt 0 ]; then
    echo "$failures no-network check(s) failed" >&2
    exit 1
fi
echo "No-network checks passed"
