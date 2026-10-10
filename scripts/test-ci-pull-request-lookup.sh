#!/bin/sh
# Tests ci-pull-request-lookup.sh with a fake `gh` first on the PATH. The fake
# answers from files, so no test reaches GitHub.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/ci-pull-request-lookup.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0
sha=1111111111111111111111111111111111111111
other=2222222222222222222222222222222222222222

ok() { echo "ok: $1"; }
not_ok() { echo "NOT OK: $1"; failed=1; }

# The fake prints what `gh api --jq` would. The list call prints $FAKE_GH/list.
# A call for pull request N prints the first line of $FAKE_GH/pull-N and drops
# it, keeping the last line, so a file can hold a run of answers. A missing
# file is a failed call. Every call is written to $FAKE_GH/calls.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_GH/calls"
for argument in "$@"; do
    case "$argument" in
        repos/*/pulls)
            [ -f "$FAKE_GH/list" ] || { echo "gh: failed" >&2; exit 1; }
            cat "$FAKE_GH/list"
            exit 0
            ;;
        repos/*/pulls/*)
            file="$FAKE_GH/pull-${argument##*/}"
            [ -s "$file" ] || { echo "gh: failed" >&2; exit 1; }
            sed -n 1p "$file"
            if [ "$(wc -l < "$file")" -gt 1 ]; then
                sed 1d "$file" > "$file.rest" && mv "$file.rest" "$file"
            fi
            exit 0
            ;;
    esac
done
echo "gh: unexpected call: $*" >&2
exit 1
FAKE
chmod +x "$work/bin/gh"

fresh() { rm -rf "$work/gh"; mkdir -p "$work/gh"; : > "$work/gh/calls"; }

lookup() { # lookup [REF] -- runs the tool; sets $output, $status and $work/stderr
    output="$(FAKE_GH="$work/gh" PATH="$work/bin:$PATH" \
        GITHUB_REPOSITORY=someone/cairn GITHUB_REPOSITORY_OWNER=someone \
        GITHUB_REF="${1:-refs/heads/feature}" GITHUB_SHA="$sha" \
        CAIRN_LOOKUP_ATTEMPTS=3 CAIRN_LOOKUP_DELAY=0 "$tool" 2>"$work/stderr")"
    status=$?
}

expect() { # expect NAME ANSWER TEXT -- stdout is exactly ANSWER, stderr holds TEXT
    if [ "$status" -ne 0 ]; then
        not_ok "$1 (exit $status)"
    elif [ "$output" != "$2" ]; then
        not_ok "$1 (printed '$output', expected '$2')"
    elif ! grep -q -- "$3" "$work/stderr"; then
        not_ok "$1 (no '$3' in: $(cat "$work/stderr"))"
    else
        ok "$1"
    fi
}

calls() { grep -c -- "$1" "$work/gh/calls"; }

# --- the one answer that skips the build

fresh; echo 7 > "$work/gh/list"; echo "true $sha" > "$work/gh/pull-7"
lookup
expect "a mergeable pull request at this commit covers the push" "covered=true" "covers this push"
grep -q -- "state=open" "$work/gh/calls" && grep -q -- "head=someone:feature" "$work/gh/calls" \
    && ok "the list call asks for open pull requests from this owner and branch" \
    || not_ok "the list call asks for open pull requests from this owner and branch ($(cat "$work/gh/calls"))"

fresh; echo 7 > "$work/gh/list"; printf 'null %s\ntrue %s\n' "$sha" "$sha" > "$work/gh/pull-7"
lookup
expect "an answer that is unknown at first and then mergeable covers the push" "covered=true" "covers this push"
[ "$(calls pulls/7)" -eq 2 ] && ok "the unknown answer was asked for again" \
    || not_ok "the unknown answer was asked for again ($(calls pulls/7) calls)"

fresh; printf '7\n9\n' > "$work/gh/list"
echo "true $sha" > "$work/gh/pull-7"; echo "true $sha" > "$work/gh/pull-9"
lookup
expect "two mergeable pull requests cover the push" "covered=true" "covers this push"

fresh; echo 7 > "$work/gh/list"; echo "true $sha" > "$work/gh/pull-7"
lookup "refs/heads/fix/a-slash"
expect "a branch name with a slash is looked up whole" "covered=true" "covers this push"
grep -q -- "head=someone:fix/a-slash" "$work/gh/calls" && ok "the list call names the whole branch" \
    || not_ok "the list call names the whole branch ($(cat "$work/gh/calls"))"

# --- every other answer runs the build

fresh; : > "$work/gh/list"
lookup
expect "no open pull request runs the build" "covered=false" "No open pull request"

fresh; echo 7 > "$work/gh/list"; echo "false $sha" > "$work/gh/pull-7"
lookup
expect "a pull request with a merge conflict runs the build" "covered=false" "merge conflict"

fresh; echo 7 > "$work/gh/list"; echo "null $sha" > "$work/gh/pull-7"
lookup
expect "mergeability that stays unknown runs the build" "covered=false" "not known to be mergeable"
[ "$(calls pulls/7)" -eq 3 ] && ok "the wait for an answer is bounded" \
    || not_ok "the wait for an answer is bounded ($(calls pulls/7) calls, expected 3)"

fresh; echo 7 > "$work/gh/list"; echo "true $other" > "$work/gh/pull-7"
lookup
expect "a mergeable pull request at another commit runs the build" "covered=false" "not known to be mergeable"

fresh; printf '7\n9\n' > "$work/gh/list"
echo "true $sha" > "$work/gh/pull-7"; echo "false $sha" > "$work/gh/pull-9"
lookup
expect "one conflicting pull request among two runs the build" "covered=false" "merge conflict"

fresh
lookup
expect "a failed list call runs the build with a warning" "covered=false" "::warning title=Pull request lookup::Listing"

fresh; echo 7 > "$work/gh/list"
lookup
expect "a failed pull request call runs the build with a warning" "covered=false" "::warning title=Pull request lookup::Reading"

fresh; echo "Not Found" > "$work/gh/list"
lookup
expect "a list that is not numbers runs the build with a warning" "covered=false" "::warning title=Pull request lookup::The pull request list"

fresh; echo 7 > "$work/gh/list"; echo "MERGEABLE" > "$work/gh/pull-7"
lookup
expect "an answer in an unexpected shape runs the build with a warning" "covered=false" "::warning title=Pull request lookup::Pull request #7 answered"

fresh; echo 7 > "$work/gh/list"; echo "true $sha" > "$work/gh/pull-7"
lookup "refs/tags/feature"
expect "a tag push runs the build" "covered=false" "is not a branch"
[ ! -s "$work/gh/calls" ] && ok "a tag push asks GitHub nothing" \
    || not_ok "a tag push asks GitHub nothing ($(cat "$work/gh/calls"))"

fresh; echo 7 > "$work/gh/list"; echo "true " > "$work/gh/pull-7"
output="$(FAKE_GH="$work/gh" PATH="$work/bin:$PATH" GITHUB_REPOSITORY=someone/cairn \
    GITHUB_REPOSITORY_OWNER=someone GITHUB_REF=refs/heads/feature GITHUB_SHA= \
    CAIRN_LOOKUP_DELAY=0 "$tool" 2>"$work/stderr")"
status=$?
expect "a missing commit runs the build with a warning" "covered=false" "::warning title=Pull request lookup::GITHUB_REPOSITORY"

# A wait count that is not a number must not turn the wait into an endless one.
fresh; echo 7 > "$work/gh/list"; echo "null $sha" > "$work/gh/pull-7"
output="$(FAKE_GH="$work/gh" PATH="$work/bin:$PATH" GITHUB_REPOSITORY=someone/cairn \
    GITHUB_REPOSITORY_OWNER=someone GITHUB_REF=refs/heads/feature GITHUB_SHA="$sha" \
    CAIRN_LOOKUP_ATTEMPTS=many CAIRN_LOOKUP_DELAY=0 "$tool" 2>"$work/stderr")"
status=$?
expect "a wait count that is not a number falls back to the default" "covered=false" "after 6 answer(s)"

exit "$failed"
