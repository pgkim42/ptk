#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-pgkim42/ptk}"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

require_gh() {
  command -v gh >/dev/null 2>&1 || fail "gh is installed"
  gh auth status >/dev/null 2>&1 || fail "gh is authenticated"
  pass "gh is authenticated"
}

assert_repo_field() {
  local jq_expr="$1"
  local description="$2"
  gh repo view "$REPO" --json description,repositoryTopics --jq "$jq_expr" | grep -q . || fail "$description"
  pass "$description"
}

assert_label() {
  local label="$1"
  gh label list --repo "$REPO" --limit 200 --json name --jq '.[] | select(.name == "'"$label"'") | .name' | grep -Fxq "$label" \
    || fail "label exists: $label"
  pass "label exists: $label"
}

assert_milestone() {
  local milestone="$1"
  gh api "repos/$REPO/milestones?state=open" --jq '.[] | select(.title == "'"$milestone"'") | .title' | grep -Fxq "$milestone" \
    || fail "milestone exists: $milestone"
  pass "milestone exists: $milestone"
}

assert_issue() {
  local title="$1"
  local milestone="$2"
  gh issue list --repo "$REPO" --state open --limit 100 --json title,milestone \
    --jq '.[] | select(.title == "'"$title"'" and .milestone.title == "'"$milestone"'") | .title' \
    | grep -Fxq "$title" || fail "issue exists in $milestone: $title"
  pass "issue exists in $milestone: $title"
}

require_gh
assert_repo_field 'select(.description == "Native macOS menu bar utility for safely monitoring and cleaning up local development ports.")' "repository description is set"
assert_repo_field 'select((.repositoryTopics // []) | map(.name) | index("macos") and index("swift") and index("menubar") and index("developer-tools") and index("port-monitor"))' "repository topics are set"

assert_label "safety"
assert_label "release"
assert_label "good first issue"
assert_label "maintenance"

assert_milestone "v0.1.0"
assert_milestone "v0.2.0"

assert_issue "Package PTK as a downloadable macOS app bundle" "v0.1.0"
assert_issue "Add README screenshot or short demo GIF" "v0.1.0"
assert_issue "Prepare v0.1.0 release notes and verification checklist" "v0.1.0"
assert_issue "Add manual refresh action to the menu bar panel" "v0.2.0"
assert_issue "Add watched-port presets for common development stacks" "v0.2.0"

pass "github-management-readiness"
