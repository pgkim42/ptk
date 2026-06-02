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
assert_contains CHANGELOG.md "## [0.1.0]"
assert_contains CHANGELOG.md "Initial public Swift-only macOS menu bar release"

assert_file docs/roadmap.md
assert_contains docs/roadmap.md "## v0.1.0"
assert_contains docs/roadmap.md "## v0.2.0"
assert_contains docs/roadmap.md "Release packaging"
assert_contains docs/roadmap.md "Manual refresh"
assert_contains docs/roadmap.md "Out of scope"
assert_contains docs/roadmap.md "force kill"

assert_contains README.md "CHANGELOG.md"
assert_contains README.md "docs/roadmap.md"
assert_contains README.ko.md "CHANGELOG.md"
assert_contains README.ko.md "docs/roadmap.md"

pass "release-readiness"
