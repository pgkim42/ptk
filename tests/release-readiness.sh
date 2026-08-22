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
  grep -Fq -- "$expected" "$path" || fail "$path contains: $expected"
  pass "$path contains: $expected"
}

validate_release_contract() {
  python3 - <<'PY'
from pathlib import Path
import re
import sys

failures = []

def require(condition, message):
    if not condition:
        failures.append(message)

def require_all(path, phrases):
    text = Path(path).read_text()
    for phrase in phrases:
        require(phrase in text, f"{path} contains: {phrase}")

changelog = Path("CHANGELOG.md").read_text()
heading_matches = re.findall(r"^## \[0\.1\.0\](?:\s|$)", changelog, re.MULTILINE)
require(len(heading_matches) == 1, "changelog has one 0.1.0 heading")
require(re.search(r"^## \[0\.[2-9]\.0\]", changelog, re.MULTILINE) is None, "changelog has no later discarded headings")
current_release = changelog
for phrase in (
    "Port-change notifications",
    "This line is not released yet",
    "disabled by default",
    "never prompt",
    "Open the PTK panel only when a notification is clicked",
    "SIGTERM`-only",
    "universal Apple Silicon and Intel",
):
    require(phrase in current_release, f"0.1.0 changelog section contains: {phrase}")

require_all("README.md", (
    "Current release preparation: `0.1.0`",
    "Published binary artifacts: none",
    "macOS 13+ on Apple Silicon and Intel",
    "off by default for new and upgraded configurations.",
    "current intersection to notify.",
    "never prompt.",
    "valid enabled configuration is saved",
    "routes blocked permission to macOS Settings.",
    "does not erase the saved opt-in intent",
    "notification opens the PTK panel only.",
    "SIGTERM` only",
    "universal binary",
    "signed PKG installer packaging",
))
require("`0.1.0`" in Path("README.ko.md").read_text(), "Korean README names release 0.1.0")
readme_ko = Path("README.ko.md").read_text()
require("공개 바이너리 배포: 없음" in readme_ko, "Korean README states no binary release")
require_all("macos/README.md", (
    "Swift/AppKit",
    "`SIGTERM`",
))
require_all("macos/Package.swift", (
    "// swift-tools-version: 6.0",
    ".macOS(.v13)",
))

if failures:
    for failure in failures:
        print(f"not ok - {failure}", file=sys.stderr)
    sys.exit(1)
PY
}

assert_file CHANGELOG.md
assert_file README.md
assert_file README.ko.md
assert_file macos/README.md
assert_file macos/Package.swift
validate_release_contract

assert_file docs/roadmap.md
assert_contains docs/roadmap.md "## v0.1.0 — current release preparation"
assert_contains docs/roadmap.md "local port-change notification"
assert_contains docs/roadmap.md "Unsigned DMG and ZIP release artifacts"
assert_contains docs/roadmap.md "manual refresh"
assert_contains docs/roadmap.md "Out of scope"
assert_contains docs/roadmap.md "force kill"

assert_file tests/package-readiness.sh
tests/package-readiness.sh
assert_file tests/release-publication-readiness-tests.sh
tests/release-publication-readiness-tests.sh

pass "release-readiness"
