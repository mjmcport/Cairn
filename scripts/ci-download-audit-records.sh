#!/bin/sh
# Downloads the audit records earlier full-suite runs uploaded, for the retry
# window in accessibility-retries.py. Records come from any run, on any branch.
#
# Usage: ci-download-audit-records.sh FOLDER
# Writes FOLDER/history/NAME.json for each of the newest records. A record
# that cannot be fetched or unpacked is left empty, and the tool names it. If
# the listing fails, the script exits 1 and makes no history folder, and the
# tool then says the count is unknown.
#
# Reads GITHUB_REPOSITORY and needs `gh` with a token that can read Actions.

folder="${1:-}"
repository="${GITHUB_REPOSITORY:-}"
if [ -z "$folder" ] || [ -z "$repository" ]; then
    echo "ci-download-audit-records: usage: ci-download-audit-records.sh FOLDER, with GITHUB_REPOSITORY set" >&2
    exit 1
fi
mkdir -p "$folder" || exit 1

# More than the window needs: this run's own record may be listed, and the
# tool takes the newest ones.
gh api --method GET "repos/$repository/actions/artifacts" -f per_page=100 \
    --jq '[.artifacts[] | select(.expired | not) | select(.name | startswith("accessibility-audits-"))]
          | sort_by(.created_at) | reverse | .[:30][] | "\(.id) \(.name)"' \
    > "$folder/artifacts.txt" || {
    echo "ci-download-audit-records: listing the artifacts failed" >&2
    exit 1
}

mkdir -p "$folder/history" || exit 1
while read -r id name; do
    record="$folder/history/$name.json"
    gh api "repos/$repository/actions/artifacts/$id/zip" > "$folder/artifact.zip" \
        && unzip -p "$folder/artifact.zip" record.json > "$record" \
        || : > "$record"
done < "$folder/artifacts.txt"
echo "Listed $(wc -l < "$folder/artifacts.txt" | tr -d ' ') earlier record(s)"
