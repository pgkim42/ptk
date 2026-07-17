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

assert_file .github/workflows/ci.yml
assert_contains .github/workflows/ci.yml "macos-latest"
assert_contains .github/workflows/ci.yml "uses: actions/checkout@v6.0.2"
assert_not_contains .github/workflows/ci.yml "uses: actions/checkout@v4"
assert_contains .github/workflows/ci.yml "swift test"
assert_contains .github/workflows/ci.yml "swift build"
assert_contains .github/workflows/ci.yml "PTK_CI_WINDOWSERVER_TEST_SKIP"
assert_contains .github/workflows/ci.yml "timeout-minutes: 5"
assert_contains .github/workflows/ci.yml "timeout-minutes: 3"
assert_contains .github/workflows/ci.yml "PTK_CI_PROCESS_TEST_SKIP"
assert_contains .github/workflows/ci.yml "PTKCoreTests.ProcessRunnerTests"
assert_contains .github/workflows/ci.yml "startCanShowPanelImmediatelyForAutomation"
assert_contains .github/workflows/ci.yml "panelClosedUsesQuietCadenceSlowerThanAllUserIntervals"
assert_contains .github/workflows/ci.yml "panelReopenRestoresNormalTenSecondCadenceAndRefreshes"
assert_contains .github/workflows/ci.yml "panelSnapshotCanBeWrittenForAutomation"
assert_contains .github/workflows/ci.yml "panelSnapshotCanRenderDockerContainerRowsForAutomation"
assert_contains .github/workflows/ci.yml "settingsSnapshotCanBeWrittenForAutomation"
assert_contains .github/workflows/ci.yml "buttonInteractionSnapshotCanBeWrittenForAutomation"
assert_contains .github/workflows/ci.yml "renderedDiagnosticRowIsTallerThanRenderedRegularRow"
assert_contains .github/workflows/ci.yml 'swift test --filter PTKCoreTests --skip "$PTK_CI_PROCESS_TEST_SKIP"'
assert_contains .github/workflows/ci.yml 'swift test --filter PTKAppTests --skip "$PTK_CI_WINDOWSERVER_TEST_SKIP"'
assert_contains .github/workflows/ci.yml "tests/open-source-readiness.sh"
assert_contains .github/workflows/ci.yml "tests/release-readiness.sh"
assert_contains .github/workflows/ci.yml "tests/ci-workflow-readiness.sh"
assert_not_contains .github/workflows/ci.yml "xcodebuild -scheme PTK"
assert_contains macos/Tests/PTKAppTests/MenuBarControllerTests.swift "@Suite(.serialized) struct MenuBarControllerTests"

pass "ci-workflow-readiness"
