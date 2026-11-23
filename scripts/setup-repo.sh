#!/usr/bin/env bash
# One-time repository setup for the secure CI/CD pipeline.
#
# Forks and repos created from a template do not copy settings, so run this
# once in your own copy. It uses the GitHub CLI (gh), signed in as a repo admin.
#
# It creates or updates:
#   - the `dev` branch (from main)
#   - environment `development` (no rules)
#   - environment `production` (required reviewer, deploys only from main)
#   - ruleset `protect-main`: PR required, N approvals, scans must pass,
#     no force-push or deletion
#   - repository variable SNYK_ORG (optional)
#
# Usage:
#   bash scripts/setup-repo.sh [--repo owner/name] [--reviewer login]
#                              [--approvals N] [--admin-bypass] [--snyk-org ID]
#
#   --admin-bypass  lets repo admins merge their own PRs once the scans pass
#                   (useful when you are the only maintainer).
#
# Windows: run in Git Bash. If gh is not on PATH, set GH to its full path, e.g.
#   GH="/c/Program Files/GitHub CLI/gh.exe" bash scripts/setup-repo.sh
set -euo pipefail

GH=${GH:-gh}
REPO=""
REVIEWER=""
APPROVALS=1
ADMIN_BYPASS=false
SNYK_ORG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO=$2; shift 2 ;;
    --reviewer)     REVIEWER=$2; shift 2 ;;
    --approvals)    APPROVALS=$2; shift 2 ;;
    --admin-bypass) ADMIN_BYPASS=true; shift ;;
    --snyk-org)     SNYK_ORG=$2; shift 2 ;;
    -h|--help)      sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$REPO" ] || REPO=$("$GH" repo view --json nameWithOwner --jq .nameWithOwner)
[ -n "$REVIEWER" ] || REVIEWER=$("$GH" api user --jq .login)
REVIEWER_ID=$("$GH" api "users/$REVIEWER" --jq .id)
DEFAULT_BRANCH=$("$GH" api "repos/$REPO" --jq .default_branch)

echo "Repository:      $REPO"
echo "Prod reviewer:   $REVIEWER"
echo "PR approvals:    $APPROVALS"
echo "Admin bypass:    $ADMIN_BYPASS"
echo

# 1. dev branch
if "$GH" api "repos/$REPO/branches/dev" --silent 2>/dev/null; then
  echo "✓ dev branch exists"
else
  SHA=$("$GH" api "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha)
  "$GH" api -X POST "repos/$REPO/git/refs" -f ref=refs/heads/dev -f sha="$SHA" --silent
  echo "✓ dev branch created from $DEFAULT_BRANCH"
fi

# 2. environments
"$GH" api -X PUT "repos/$REPO/environments/development" --silent
echo "✓ environment: development (no rules)"

"$GH" api -X PUT "repos/$REPO/environments/production" --silent --input - <<EOF
{"wait_timer":0,"prevent_self_review":false,
 "reviewers":[{"type":"User","id":$REVIEWER_ID}],
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
if ! "$GH" api "repos/$REPO/environments/production/deployment-branch-policies" \
     --jq '.branch_policies[].name' | grep -qx "$DEFAULT_BRANCH"; then
  "$GH" api -X POST "repos/$REPO/environments/production/deployment-branch-policies" \
    -f name="$DEFAULT_BRANCH" -f type=branch --silent
fi
echo "✓ environment: production (reviewer $REVIEWER, deploys only from $DEFAULT_BRANCH)"

# 3. ruleset protecting the default branch
if [ "$ADMIN_BYPASS" = true ]; then
  BYPASS='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
else
  BYPASS='[]'
fi
RULESET=$(cat <<EOF
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "bypass_actors": $BYPASS,
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": $APPROVALS,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "required_status_checks": [
        {"context": "SAST (Snyk Code)", "integration_id": 15368},
        {"context": "SCA (Snyk)", "integration_id": 15368},
        {"context": "DAST (OWASP ZAP)", "integration_id": 15368}]}}
  ]
}
EOF
)
RULESET_ID=$("$GH" api "repos/$REPO/rulesets" --jq '.[] | select(.name=="protect-main") | .id' | head -1)
if [ -n "$RULESET_ID" ]; then
  echo "$RULESET" | "$GH" api -X PUT "repos/$REPO/rulesets/$RULESET_ID" --input - --silent
  echo "✓ ruleset protect-main updated"
else
  echo "$RULESET" | "$GH" api -X POST "repos/$REPO/rulesets" --input - --silent
  echo "✓ ruleset protect-main created"
fi

# 4. Snyk organization (optional)
if [ -n "$SNYK_ORG" ]; then
  "$GH" variable set SNYK_ORG --repo "$REPO" --body "$SNYK_ORG"
  echo "✓ variable SNYK_ORG set"
fi

# 5. Snyk token check (the script never reads or sets the token itself)
echo
if "$GH" api "repos/$REPO/actions/secrets" --jq '.secrets[].name' | grep -qx SNYK_TOKEN; then
  echo "✓ SNYK_TOKEN secret found"
else
  echo "! SNYK_TOKEN secret is missing. Add it with:"
  echo "    gh secret set SNYK_TOKEN --repo $REPO"
fi
echo
echo "Done. Push to 'dev', then open a PR from dev to $DEFAULT_BRANCH."
