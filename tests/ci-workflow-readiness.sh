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

validate_workflow() {
  python3 - <<'PY'
from pathlib import Path
import re
import sys

workflow = Path(".github/workflows/ci.yml").read_text()
failures = []

def require(condition, message):
    if not condition:
        failures.append(message)

swift_job = re.search(
    r"^  swift:\n(?P<body>(?:(?!^  [A-Za-z0-9_-]+:).*\n)*)",
    workflow + "\n",
    re.MULTILINE,
)
require(swift_job is not None, "active swift job is present")
if swift_job:
    job = swift_job.group("body")
    require(re.search(r"^    runs-on: macos-latest$", job, re.MULTILINE), "swift job uses macos-latest")
    require(re.search(r"^    timeout-minutes: 5$", job, re.MULTILINE), "swift job has a five-minute timeout")

    steps = list(re.finditer(
        r"^      - name: (?P<name>[^\n]+)\n(?P<body>(?:(?!^      - ).*\n)*)",
        job + "\n",
        re.MULTILINE,
    ))
    test_steps = [step for step in steps if step.group("name") == "Test package"]
    require(len(test_steps) == 1, "exactly one active Test package step exists")
    if len(test_steps) == 1:
        body = test_steps[0].group("body")
        require(re.search(r"^        timeout-minutes: 2$", body, re.MULTILINE), "Test package has a two-minute timeout")
        require(re.search(r"^        working-directory: macos$", body, re.MULTILINE), "Test package runs in macos")
        command = re.search(r"^        run: swift test --filter '([^']+)'$", body, re.MULTILINE)
        require(command is not None, "Test package uses one filtered swift test command")
        if command:
            expected = {
                "AppSettingsTests", "KillSafetyTests", "LsofParserTests", "MenuModelTests",
                "PortRangeParserTests", "PortScannerTests", "ProcessLookupTests",
                "RefreshSchedulerTests", "PortChangeNotificationCoordinatorTests",
                "UserNotificationClientTests", "PortChangeNotificationIntegrationTests",
                "PortChangeNotificationAccessibilityTests",
            }
            actual = command.group(1).split("|")
            require(set(actual) == expected and len(actual) == len(expected), "filtered test suites match the bounded set exactly")
    normalized_workflow = re.sub(r"\\\s*\n\s*", " ", workflow)
    require(
        len(re.findall(r"\bswift\s+test\b", normalized_workflow)) == 1,
        "workflow has exactly one swift test command",
    )
    build_steps = [step for step in steps if step.group("name") == "Build package"]
    require(
        len(build_steps) == 1 and re.search(r"^        run: swift build$", build_steps[0].group("body"), re.MULTILINE),
        "active Build package step runs swift build",
    )

forbidden = (
    r"continue-on-error:\s*true",
    r"\|\|\s*true",
    r"set\s+\+e",
    r"--skip(?:\b|=)",
    r"PTK_CI_[A-Z_]*SKIP",
    r"(?:-suppress-warnings|--disable-warnings|SWIFT_SUPPRESS_WARNINGS|GCC_WARN_INHIBIT_ALL_WARNINGS)",
    r"(?:^|\s)(?:1?>|2>)\s*/dev/null",
)
for pattern in forbidden:
    require(re.search(pattern, workflow, re.MULTILINE) is None, f"workflow rejects suppression: {pattern}")

for command in (
    "tests/open-source-readiness.sh",
    "tests/release-readiness.sh",
    "tests/ci-workflow-readiness.sh",
):
    require(command in workflow, f"repository metadata runs {command}")

require("uses: actions/checkout@v6.0.2" in workflow, "workflow uses the pinned checkout action")
require("uses: actions/checkout@v4" not in workflow, "workflow does not use checkout v4")
require(re.search(r"\bxcodebuild\b", workflow) is None, "workflow does not run xcodebuild")

if failures:
    for failure in failures:
        print(f"not ok - {failure}", file=sys.stderr)
    sys.exit(1)
PY
}

assert_file .github/workflows/ci.yml
validate_workflow
assert_contains macos/Tests/PTKAppTests/MenuBarControllerTests.swift "@Suite(.serialized) struct MenuBarControllerTests"

pass "ci-workflow-readiness"
