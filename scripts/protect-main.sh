#!/bin/sh
# Protects the main branch: the "Build and test" check must pass before a pull
# request can merge, and force pushes and deletion are refused.
#
# Repository administrators can still push directly, which the one-commit-per-
# step workflow relies on. A change that touches only documents starts no
# "Build and test" run, so only an administrator can merge one. GitHub offers
# branch protection on a private repository only with GitHub Pro.

set -eu
repository="${1:-mjmcport/Cairn}"

gh api --method PUT "repos/$repository/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Build and test"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
echo "main is protected on $repository"
