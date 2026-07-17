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
  gh repo view "$REPO" --json description,repositoryTopics,hasIssuesEnabled --jq "$jq_expr" | grep -q . || fail "$description"
  pass "$description"
}

assert_label() {
  local label="$1"
  gh label list --repo "$REPO" --limit 200 --json name --jq '.[] | select(.name == "'"$label"'") | .name' | grep -Fxq "$label" \
    || fail "label exists: $label"
  pass "label exists: $label"
}


require_gh
assert_repo_field 'select(.description == "Native macOS menu bar utility for safely monitoring and cleaning up local development ports.")' "repository description is set"
assert_repo_field 'select((.repositoryTopics // []) | map(.name) | index("macos") and index("swift") and index("menubar") and index("developer-tools") and index("port-monitor"))' "repository topics are set"
assert_repo_field 'select(.hasIssuesEnabled == true)' "issue tracker is enabled"

assert_label "bug"
assert_label "documentation"
assert_label "enhancement"
assert_label "good first issue"
assert_label "maintenance"
assert_label "release"
assert_label "safety"
assert_label "status: not started"
assert_label "status: in progress"
assert_label "status: completed"

pass "github-management-readiness"
