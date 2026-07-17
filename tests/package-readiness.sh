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
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ptk-package-readiness.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

setup_fixture() {
  local name="$1"
  local root="$TEST_TMP/$name"

  mkdir -p "$root/scripts" "$root/macos" "$root/mock-bin"
  cp scripts/package-release.sh "$root/scripts/package-release.sh"

  cat > "$root/mock-bin/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$PTK_TEST_ROOT/macos/.build/release"
printf '#!/usr/bin/env bash\nexit 0\n' > "$PTK_TEST_ROOT/macos/.build/release/PTK"
chmod +x "$PTK_TEST_ROOT/macos/.build/release/PTK"
EOF

  cat > "$root/mock-bin/hdiutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  create)
    if [[ "${FAIL_HDIUTIL_CREATE:-0}" -eq 1 ]]; then
      exit 1
    fi
    output="${!#}"
    printf 'test dmg\n' > "$output"
    ;;
  verify)
    [[ -s "$2" ]]
    ;;
  *)
    exit 64
    ;;
esac
EOF

  chmod +x "$root/mock-bin/swift" "$root/mock-bin/hdiutil"
  printf '%s\n' "$root"
}

assert_no_temporary_output() {
  local root="$1"
  local candidates=("$root"/.ptk-release.*)

  [[ ! -e "${candidates[0]}" ]] || fail "temporary release output is cleaned"
  pass "temporary release output is cleaned"
}

test_successful_package() {
  local root
  local plist

  root="$(setup_fixture success)"
  PATH="$root/mock-bin:$PATH" PTK_TEST_ROOT="$root" \
    "$root/scripts/package-release.sh" 0.5.0 42 >/dev/null

  plist="$root/dist/PTK.app/Contents/Info.plist"
  [[ -x "$root/dist/PTK.app/Contents/MacOS/PTK" ]] || fail "generated app contains an executable"
  [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == "0.5.0" ]] ||
    fail "generated app contains the display version"
  [[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == "42" ]] ||
    fail "generated app contains the build version"
  unzip -tqq "$root/dist/PTK-macos-0.5.0-unsigned.zip"
  [[ -s "$root/dist/PTK-macos-0.5.0-unsigned.dmg" ]] || fail "generated DMG is non-empty"
  assert_no_temporary_output "$root"
  pass "generated release artifacts are structurally valid"
}

test_invalid_versions() {
  local root
  local arguments

  root="$(setup_fixture invalid)"
  for arguments in \
    "release 1" \
    "0.5 1" \
    "0.5.0-beta 1" \
    "0.5.0 release" \
    "0.5.0 1.2.3.4" \
    "0.5.0 12345"; do
    if PATH="$root/mock-bin:$PATH" PTK_TEST_ROOT="$root" \
      "$root/scripts/package-release.sh" $arguments >/dev/null 2>&1; then
      fail "invalid version is rejected: $arguments"
    fi
  done

  [[ ! -e "$root/dist" ]] || fail "invalid versions create no output"
  assert_no_temporary_output "$root"
  pass "invalid display and build versions are rejected"
}

test_failure_preserves_previous_release() {
  local root

  root="$(setup_fixture failure)"
  mkdir -p "$root/dist/PTK.app"
  printf 'old app\n' > "$root/dist/PTK.app/marker"
  printf 'old zip\n' > "$root/dist/PTK-macos-0.5.0-unsigned.zip"
  printf 'old dmg\n' > "$root/dist/PTK-macos-0.5.0-unsigned.dmg"

  if PATH="$root/mock-bin:$PATH" PTK_TEST_ROOT="$root" FAIL_HDIUTIL_CREATE=1 \
    "$root/scripts/package-release.sh" 0.5.0 42 >/dev/null 2>&1; then
    fail "failed packaging returns a failure"
  fi

  [[ "$(< "$root/dist/PTK.app/marker")" == "old app" ]] || fail "previous app is preserved"
  [[ "$(< "$root/dist/PTK-macos-0.5.0-unsigned.zip")" == "old zip" ]] ||
    fail "previous ZIP is preserved"
  [[ "$(< "$root/dist/PTK-macos-0.5.0-unsigned.dmg")" == "old dmg" ]] ||
    fail "previous DMG is preserved"
  assert_no_temporary_output "$root"
  pass "failed packaging preserves previous artifacts"
}

test_symlinked_output_is_rejected() {
  local root

  root="$(setup_fixture symlink-directory)"
  mkdir -p "$root/external"
  printf 'keep\n' > "$root/external/marker"
  ln -s "$root/external" "$root/dist"

  if PATH="$root/mock-bin:$PATH" PTK_TEST_ROOT="$root" \
    "$root/scripts/package-release.sh" 0.5.0 42 >/dev/null 2>&1; then
    fail "symlinked output directory is rejected"
  fi

  [[ "$(< "$root/external/marker")" == "keep" ]] || fail "external output target is untouched"
  assert_no_temporary_output "$root"

  root="$(setup_fixture symlink-file)"
  mkdir -p "$root/dist" "$root/external"
  printf 'keep\n' > "$root/external/archive"
  ln -s "$root/external/archive" "$root/dist/PTK-macos-0.5.0-unsigned.zip"

  if PATH="$root/mock-bin:$PATH" PTK_TEST_ROOT="$root" \
    "$root/scripts/package-release.sh" 0.5.0 42 >/dev/null 2>&1; then
    fail "symlinked artifact path is rejected"
  fi

  [[ "$(< "$root/external/archive")" == "keep" ]] || fail "external artifact target is untouched"
  assert_no_temporary_output "$root"
  pass "symlinked output paths are rejected safely"
}

assert_file scripts/package-release.sh
assert_executable scripts/package-release.sh
assert_contains scripts/package-release.sh "PTK.app"
assert_contains scripts/package-release.sh 'PTK-macos-$DISPLAY_VERSION-unsigned.zip'
assert_contains scripts/package-release.sh 'PTK-macos-$DISPLAY_VERSION-unsigned.dmg'
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

test_successful_package
test_invalid_versions
test_failure_preserves_previous_release
test_symlinked_output_is_rejected

pass "package-readiness"
