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
heading_patterns = (
    r"^## \[0\.6\.0\](?:\s|$)",
    r"^## \[0\.5\.0\](?:\s|$)",
)
heading_matches = [re.findall(pattern, changelog, re.MULTILINE) for pattern in heading_patterns]
positions = [
    match.start() if (match := re.search(pattern, changelog, re.MULTILINE)) else -1
    for pattern in heading_patterns
]
require(all(position >= 0 for position in positions), "changelog has 0.6.0 and 0.5.0 headings")
require(positions == sorted(positions), "changelog chronology is 0.6.0 then 0.5.0")
for version, matches in zip(("0.6.0", "0.5.0"), heading_matches):
    require(len(matches) == 1, f"changelog has one {version} heading")
if positions[0] >= 0 and positions[1] >= 0:
    current_release = changelog[positions[0]:positions[1]]
    for phrase in (
        "Port-change notifications",
        "This line is not released yet",
        "disabled by default",
        "never prompt",
        "Open the PTK panel only when a notification is clicked",
        "SIGTERM`-only",
        "universal Apple Silicon and Intel",
    ):
        require(phrase in current_release, f"0.6.0 changelog section contains: {phrase}")

require_all("README.md", (
    "Current release preparation: `0.6.0`",
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
require("`0.6.0`" in Path("README.ko.md").read_text(), "Korean README names release 0.6.0")
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
assert_contains docs/roadmap.md "## v0.6.0 — current release preparation"
assert_contains docs/roadmap.md "local port-change notification"
assert_contains docs/roadmap.md "## Archived planning milestones"
assert_contains docs/roadmap.md "Unsigned DMG and ZIP release artifacts"
assert_contains docs/roadmap.md "manual refresh"
assert_contains docs/roadmap.md "Out of scope"
assert_contains docs/roadmap.md "force kill"

assert_file tests/package-readiness.sh
tests/package-readiness.sh
assert_file tests/release-publication-readiness-tests.sh
tests/release-publication-readiness-tests.sh

pass "release-readiness"
