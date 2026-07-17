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
    ):
        require(phrase in current_release, f"0.6.0 changelog section contains: {phrase}")

require_all("README.md", (
    "Current release preparation: `0.6.0`",
    "Latest published artifacts: `0.5.0`",
    "macOS 13+",
    "off by default for new and upgraded configurations.",
    "current intersection to notify.",
    "never prompt.",
    "valid enabled configuration is saved",
    "routes blocked permission to macOS Settings.",
    "does not erase the saved opt-in intent",
    "notification opens the PTK panel only.",
    "SIGTERM` only",
    "signed PKG installer packaging",
))
require_all("README.ko.md", (
    "현재 릴리스 준비 버전: `0.6.0`",
    "최신 공개 배포 파일: `0.5.0`",
    "macOS 13 이상",
    "기본값이 꺼짐입니다.",
    "교집합에 있어야 합니다.",
    "절대 띄우지 않습니다.",
    "설정을 저장한 뒤에만",
    "macOS Settings로 연결합니다.",
    "켜기 상태나 선택 표현식이 지워지지 않습니다.",
    "PTK 패널만 엽니다.",
    "`SIGTERM`만",
    "서명된 PKG 설치 패키지",
))
require_all("macos/README.md", (
    "기본으로\n끈 상태",
    "두 표현식의 교집합",
    "권한 요청을 절대\n띄우지 않습니다.",
    "유효한 켜기 설정을\n저장한 뒤에만",
    "macOS Settings로 연결",
    "켜기 상태와 포트 표현식은 유지합니다.",
    "PTK 패널만 엽니다.",
    "Swift/AppKit",
    "프로세스 종료는 재검증 뒤 `SIGTERM`만 사용합니다.",
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

pass "release-readiness"
