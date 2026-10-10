#!/bin/sh
# Decides whether a push may skip the macOS job because a pull-request run
# covers the commit. Prints one line for $GITHUB_OUTPUT, `covered=true` or
# `covered=false`; the reason goes to stderr.
#
# The answer is `covered=true` only when every open pull request for the branch
# has this commit as its head and GitHub reports it mergeable. GitHub starts no
# pull-request run while a pull request has a merge conflict, so a conflict
# means nothing else builds the commit. Every other answer is `covered=false`
# and the build runs: no pull request, a conflict, mergeability still unknown
# after a short wait, a push that is not to a branch (a tag), or a failed call.
#
# Reads GITHUB_REPOSITORY, GITHUB_REPOSITORY_OWNER, GITHUB_REF and GITHUB_SHA,
# which the runner sets, and needs `gh` with a token that can read pull
# requests. GitHub works mergeability out after the push, so the answer is
# asked for up to CAIRN_LOOKUP_ATTEMPTS times (default 6), CAIRN_LOOKUP_DELAY
# seconds apart (default 5).

repository="${GITHUB_REPOSITORY:-}"
owner="${GITHUB_REPOSITORY_OWNER:-}"
ref="${GITHUB_REF:-}"
sha="${GITHUB_SHA:-}"
attempts="${CAIRN_LOOKUP_ATTEMPTS:-6}"
delay="${CAIRN_LOOKUP_DELAY:-5}"
case "$attempts" in '' | *[!0-9]*) attempts=6 ;; esac
case "$delay" in '' | *[!0-9]*) delay=5 ;; esac

build() { # build REASON -- the build runs
    echo "$1" >&2
    echo "covered=false"
    exit 0
}

unsure() { # unsure REASON -- the build runs, with a warning on the run
    build "::warning title=Pull request lookup::$1, so the build runs."
}

if [ -z "$repository" ] || [ -z "$owner" ] || [ -z "$sha" ]; then
    unsure "GITHUB_REPOSITORY, GITHUB_REPOSITORY_OWNER or GITHUB_SHA is not set"
fi
case "$ref" in
    refs/heads/?*) branch="${ref#refs/heads/}" ;;
    *) build "'$ref' is not a branch, so no pull-request run covers this push: the build runs." ;;
esac

numbers="$(gh api --method GET "repos/$repository/pulls" \
    -f state=open -f head="$owner:$branch" --jq '.[].number')" \
    || unsure "Listing the pull requests for $owner:$branch failed"
if [ -z "$numbers" ]; then
    build "No open pull request for $owner:$branch: the build runs."
fi

for number in $numbers; do
    case "$number" in
        *[!0-9]*) unsure "The pull request list held '$number', which is not a number" ;;
    esac
    attempt=1
    while :; do
        answer="$(gh api --method GET "repos/$repository/pulls/$number" \
            --jq '"\(.mergeable) \(.head.sha)"')" \
            || unsure "Reading pull request #$number failed"
        case "$answer" in
            "true $sha") break ;;
            "false "*) build "Pull request #$number has a merge conflict, so no pull-request run starts: the build runs." ;;
            # Not worked out yet, or the pull request is not at this commit yet.
            "null "* | "true "*) ;;
            *) unsure "Pull request #$number answered '$answer'" ;;
        esac
        if [ "$attempt" -ge "$attempts" ]; then
            build "Pull request #$number is not known to be mergeable at $sha after $attempt answer(s) ('$answer'): the build runs."
        fi
        attempt=$((attempt + 1))
        sleep "$delay"
    done
    echo "Pull request #$number is mergeable at $sha." >&2
done

echo "Every open pull request for $owner:$branch is mergeable: the pull-request run covers this push." >&2
echo "covered=true"
