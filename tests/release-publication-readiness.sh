#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-${GITHUB_REPOSITORY:-pgkim42/ptk}}"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || fail "gh is installed"

RELEASES_FILE="$(mktemp "${TMPDIR:-/tmp}/ptk-releases.XXXXXX")"
trap 'rm -f "$RELEASES_FILE"' EXIT

gh api "repos/$REPO/releases?per_page=100" > "$RELEASES_FILE" ||
  fail "GitHub releases are readable for $REPO"

python3 - "$RELEASES_FILE" <<'PY'
from pathlib import Path
import json
import re
import sys

releases = json.loads(Path(sys.argv[1]).read_text())
public_releases = [release for release in releases if not release.get("draft")]
readme = Path("README.md").read_text()
korean_readme = Path("README.ko.md").read_text()
failures = []


def require(condition, message):
    if not condition:
        failures.append(message)


match = re.search(r"^- Published binary artifacts: (?P<value>.+)$", readme, re.MULTILINE)
require(match is not None, "README declares the published binary artifact state")

if match:
    documented = match.group("value").strip().strip("`")
    if documented == "none":
        require(not public_releases, "README's no-release claim matches public GitHub Releases")
        require("- 공개 바이너리 배포: 없음" in korean_readme, "Korean README also declares no binary release")
        require(" from GitHub Releases" not in readme, "English README has no unavailable download instruction")
        require("GitHub Releases에서" not in korean_readme, "Korean README has no unavailable download instruction")
    else:
        candidates = [
            release
            for release in public_releases
            if release.get("tag_name") in {documented, f"v{documented}"}
        ]
        require(len(candidates) == 1, f"GitHub has one public release for {documented}")
        latest_release = max(
            public_releases,
            key=lambda release: release.get("published_at") or release.get("created_at") or "",
        ) if public_releases else None
        require(
            latest_release is not None
            and latest_release.get("tag_name") in {documented, f"v{documented}"},
            f"README names the latest public release ({documented})",
        )
        require(f"`{documented}`" in korean_readme, "Korean README names the same published version")
        if len(candidates) == 1:
            assets = {asset.get("name") for asset in candidates[0].get("assets", [])}
            require(
                f"PTK-macos-{documented}-unsigned.dmg" in assets,
                "documented release has the DMG asset",
            )
            require(
                f"PTK-macos-{documented}-unsigned.zip" in assets,
                "documented release has the ZIP asset",
            )

if failures:
    for failure in failures:
        print(f"not ok - {failure}", file=sys.stderr)
    sys.exit(1)

print("ok - documented binary publication state matches GitHub Releases")
PY
