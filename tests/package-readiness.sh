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

assert_executable() {
  local path="$1"
  [[ -x "$path" ]] || fail "$path is executable"
  pass "$path is executable"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq "$expected" "$path" || fail "$path contains: $expected"
  pass "$path contains: $expected"
}

assert_file scripts/package-release.sh
assert_executable scripts/package-release.sh
assert_contains scripts/package-release.sh "PTK.app"
assert_contains scripts/package-release.sh 'PTK-macos-$VERSION-unsigned.zip'
assert_contains scripts/package-release.sh 'PTK-macos-$VERSION-unsigned.dmg'
assert_contains scripts/package-release.sh "hdiutil create"
assert_contains scripts/package-release.sh "CFBundlePackageType"
assert_contains scripts/package-release.sh "LSMinimumSystemVersion"

assert_contains README.md "PTK-macos-0.5.0-unsigned.dmg"
assert_contains README.md "This release is unsigned"
assert_contains README.md "Right-click PTK.app and choose **Open**"
assert_contains README.md "PTK does not include automatic updates yet"
assert_contains README.md "replace the app manually"

assert_contains README.ko.md "PTK-macos-0.5.0-unsigned.dmg"
assert_contains README.ko.md "현재 릴리스는 서명되지 않았습니다"
assert_contains README.ko.md "PTK.app을 우클릭하고 **열기**를 선택"
assert_contains README.ko.md "아직 자동 업데이트를 포함하지 않습니다"
assert_contains README.ko.md "앱을 수동으로 교체"

assert_contains docs/roadmap.md "Unsigned DMG and ZIP release artifacts"
assert_contains tests/release-readiness.sh "tests/package-readiness.sh"
assert_contains tests/open-source-readiness.sh "tests/package-readiness.sh"

pass "package-readiness"
