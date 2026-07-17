#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "$path exists"
  pass "$path exists"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq "$expected" "$path" || fail "$path contains: $expected"
  pass "$path contains: $expected"
}

assert_file CHANGELOG.md
assert_contains CHANGELOG.md "## [Unreleased]"
assert_contains CHANGELOG.md "## [0.5.0]"
assert_contains CHANGELOG.md "Current Swift-only macOS release line"
assert_contains CHANGELOG.md "SIGTERM"
assert_contains CHANGELOG.md "cd macos && swift test"
assert_contains CHANGELOG.md "xcodebuild -scheme PTK"
assert_contains CHANGELOG.md "### Known limitations"

assert_file docs/roadmap.md
assert_contains docs/roadmap.md "## v0.5.0 — current release line"
assert_contains docs/roadmap.md "## Archived planning milestones"
assert_contains docs/roadmap.md "Unsigned DMG and ZIP release artifacts"
assert_contains docs/roadmap.md "manual refresh"
assert_contains docs/roadmap.md "Out of scope"
assert_contains docs/roadmap.md "force kill"

assert_contains README.md "CHANGELOG.md"
assert_contains README.md "docs/roadmap.md"
assert_contains README.md "PTK-macos-0.5.0-unsigned.dmg"
assert_contains README.ko.md "CHANGELOG.md"
assert_contains README.ko.md "docs/roadmap.md"
assert_contains README.ko.md "PTK-macos-0.5.0-unsigned.dmg"
assert_contains tests/package-readiness.sh "package-readiness"

tests/package-readiness.sh

pass "release-readiness"
