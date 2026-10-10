#!/bin/sh
# Tests ci-download-audit-records.sh with a fake `gh` first on the PATH, and
# hands what it leaves behind to accessibility-retries.py, which reads it.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/ci-download-audit-records.sh"
base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
# The output folder has a space in its path.
work="$base/with space"
folder="$work/accessibility"
mkdir -p "$work/bin"
failed=0

ok() { echo "ok: $1"; }
not_ok() { echo "NOT OK: $1"; failed=1; }

# The fake prints what `gh api` would. The listing prints $FAKE_GH/list, in
# the "ID NAME" lines the tool's --jq filter produces. A download of artifact
# ID prints $FAKE_GH/zip-ID. A missing file is a failed call.
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
for argument in "$@"; do
    case "$argument" in
        repos/*/actions/artifacts) file="$FAKE_GH/list" ;;
        repos/*/actions/artifacts/*/zip) id="${argument%/zip}"; file="$FAKE_GH/zip-${id##*/}" ;;
        *) continue ;;
    esac
    [ -f "$file" ] || { echo "gh: failed" >&2; exit 1; }
    cat "$file"
    exit 0
done
echo "gh: unexpected call: $*" >&2
exit 1
FAKE
chmod +x "$work/bin/gh"

fresh() { rm -rf "$work/gh" "$folder" "$work/pack"; mkdir -p "$work/gh" "$work/pack"; }

artifact() { # artifact ID FILE RUN RECORDED RETRIES -- a zip that holds FILE
    printf '{"run": "%s", "recorded": "%s", "audits": 3, "retries": %s, "retriedScreens": []}\n' \
        "$3" "$4" "$5" > "$work/pack/$2"
    # zip adds .zip to a name without a suffix, so the file is renamed after.
    (cd "$work/pack" && zip -q "$work/pack/packed.zip" "$2" && rm -f "$2") \
        && mv "$work/pack/packed.zip" "$work/gh/zip-$1"
}

download() { # download -- runs the tool; sets $output and $status
    output="$(FAKE_GH="$work/gh" PATH="$work/bin:$PATH" GITHUB_REPOSITORY=someone/cairn \
        "$tool" "$folder" 2>"$work/stderr")"
    status=$?
}

check() { # check -- the retry window over what the tool left; sets $checked
    printf '{"run": "900-1", "recorded": "2026-12-01T00:00:00Z", "audits": 3, "retries": 1, "retriedScreens": []}\n' \
        > "$work/record.json"
    checked="$(python3 "$here/accessibility-retries.py" check "$work/record.json" "$folder/history" 2>&1)"
}

# --- every record arrives

fresh
printf '11 accessibility-audits-1-1\n12 accessibility-audits-2-1\n' > "$work/gh/list"
artifact 11 record.json 1-1 "2026-11-01T00:00:00Z" 1
artifact 12 record.json 2-1 "2026-11-02T00:00:00Z" 0
download
[ "$status" -eq 0 ] && echo "$output" | grep -q "Listed 2 earlier record(s)" \
    && grep -q '"run": "1-1"' "$folder/history/accessibility-audits-1-1.json" \
    && grep -q '"run": "2-1"' "$folder/history/accessibility-audits-2-1.json" \
    && ok "each listed record is unpacked under its artifact's name" \
    || not_ok "each listed record is unpacked under its artifact's name ($status: $output $(cat "$work/stderr"))"
check
echo "$checked" | grep -q "2 retries in the last 3 full-suite runs" \
    && ok "the retry window counts the downloaded records" \
    || not_ok "the retry window counts the downloaded records ($checked)"

# --- a record that cannot be fetched or unpacked is left empty and named

fresh
printf '11 accessibility-audits-1-1\n12 accessibility-audits-2-1\n13 accessibility-audits-3-1\n' > "$work/gh/list"
artifact 11 record.json 1-1 "2026-11-01T00:00:00Z" 1
artifact 13 other.json 3-1 "2026-11-03T00:00:00Z" 1
download
[ "$status" -eq 0 ] \
    && [ -s "$folder/history/accessibility-audits-1-1.json" ] \
    && [ -f "$folder/history/accessibility-audits-2-1.json" ] && [ ! -s "$folder/history/accessibility-audits-2-1.json" ] \
    && [ -f "$folder/history/accessibility-audits-3-1.json" ] && [ ! -s "$folder/history/accessibility-audits-3-1.json" ] \
    && ok "a failed download and a zip without record.json each leave an empty, named record" \
    || not_ok "a failed download and a zip without record.json each leave an empty, named record ($status: $(ls -l "$folder/history" 2>&1))"
check
echo "$checked" | grep -q "2 retries in the last 2 full-suite runs" \
    && echo "$checked" | grep -q "Skipped an earlier record that could not be read: accessibility-audits-2-1.json" \
    && echo "$checked" | grep -q "Skipped an earlier record that could not be read: accessibility-audits-3-1.json" \
    && ok "the retry window names the empty records and counts the rest" \
    || not_ok "the retry window names the empty records and counts the rest ($checked)"

# --- no earlier records

fresh
: > "$work/gh/list"
download
[ "$status" -eq 0 ] && echo "$output" | grep -q "Listed 0 earlier record(s)" && [ -d "$folder/history" ] \
    && [ -z "$(ls "$folder/history")" ] \
    && ok "an empty listing leaves an empty history folder" \
    || not_ok "an empty listing leaves an empty history folder ($status: $output)"

# --- a failed listing

fresh
download
[ "$status" -eq 1 ] && [ ! -e "$folder/history" ] && grep -q "listing the artifacts failed" "$work/stderr" \
    && ok "a failed listing exits 1 and makes no history folder" \
    || not_ok "a failed listing exits 1 and makes no history folder ($status: $(cat "$work/stderr"))"
check
echo "$checked" | grep -q "count is unknown" \
    && ok "the retry window then says the count is unknown" \
    || not_ok "the retry window then says the count is unknown ($checked)"

# --- misuse

output="$(FAKE_GH="$work/gh" PATH="$work/bin:$PATH" GITHUB_REPOSITORY=someone/cairn "$tool" 2>"$work/stderr")"
[ $? -eq 1 ] && grep -q "usage" "$work/stderr" && ok "a missing folder argument is an error" \
    || not_ok "a missing folder argument is an error"

exit "$failed"
