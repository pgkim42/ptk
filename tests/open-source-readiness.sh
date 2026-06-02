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

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  ! grep -Fq "$unexpected" "$path" || fail "$path does not contain: $unexpected"
  pass "$path does not contain: $unexpected"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "$path is absent"
  pass "$path is absent"
}

assert_file LICENSE
assert_contains LICENSE "BSD Zero Clause License"
assert_contains LICENSE "Permission to use, copy, modify, and/or distribute this software"
assert_contains LICENSE "THE SOFTWARE IS PROVIDED \"AS IS\""

assert_contains README.md "SPDX-License-Identifier: 0BSD"
assert_contains README.md "CONTRIBUTING.md"
assert_contains README.md "SECURITY.md"
assert_contains README.ko.md "SPDX-License-Identifier: 0BSD"
assert_contains README.ko.md "CONTRIBUTING.md"
assert_contains README.ko.md "SECURITY.md"

assert_file CONTRIBUTING.md
assert_contains CONTRIBUTING.md "cd macos && swift test"
assert_contains CONTRIBUTING.md "cd macos && swift build"
assert_contains CONTRIBUTING.md "SIGTERM only"
assert_contains CONTRIBUTING.md "Do not add Rust, Tauri, Node, or a separate CLI runtime"

assert_file SECURITY.md
assert_contains SECURITY.md "Do not post secrets"
assert_contains SECURITY.md "GitHub private vulnerability reporting"
assert_contains SECURITY.md "private reporting channel"
assert_contains SECURITY.md "exploit"
assert_contains SECURITY.md "process termination"

assert_file CODE_OF_CONDUCT.md
assert_contains CODE_OF_CONDUCT.md "Be kind"
assert_contains CODE_OF_CONDUCT.md "good faith"
assert_contains CODE_OF_CONDUCT.md "Reporting Concerns"
assert_contains CODE_OF_CONDUCT.md "Maintainer Response"
assert_contains CODE_OF_CONDUCT.md "Scope"
assert_contains CODE_OF_CONDUCT.md "GitHub reporting tools"

assert_file .github/workflows/ci.yml
assert_contains .github/workflows/ci.yml "macos-latest"
assert_contains .github/workflows/ci.yml "swift test"
assert_contains .github/workflows/ci.yml "swift build"
assert_contains .github/workflows/ci.yml "tests/release-readiness.sh"
assert_contains .github/workflows/ci.yml "tests/ci-workflow-readiness.sh"
assert_not_contains .github/workflows/ci.yml "xcodebuild -scheme PTK"

assert_file .github/ISSUE_TEMPLATE/bug_report.yml
assert_file .github/ISSUE_TEMPLATE/feature_request.yml
assert_file .github/pull_request_template.md
assert_contains .github/pull_request_template.md "Process termination safety"
assert_contains .github/pull_request_template.md "Swift-only runtime boundary"

assert_contains .gitignore ".codegraph/"
assert_not_exists package.json
assert_not_exists package-lock.json
assert_not_exists src-tauri
assert_not_exists ui

pass "open-source-readiness"
