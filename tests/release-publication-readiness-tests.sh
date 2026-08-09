#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ptk-publication-tests.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$FIXTURE_ROOT/bin" "$FIXTURE_ROOT/work"
cp "$ROOT_DIR/tests/release-publication-readiness.sh" "$FIXTURE_ROOT/work/check.sh"

cat > "$FIXTURE_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "api" ]]
cat "$PTK_RELEASE_FIXTURE"
EOF
chmod +x "$FIXTURE_ROOT/bin/gh" "$FIXTURE_ROOT/work/check.sh"

write_readmes() {
  local version="$1"
  if [[ "$version" == "none" ]]; then
    printf '%s\n' '- Published binary artifacts: none' > "$FIXTURE_ROOT/work/README.md"
    printf '%s\n' '- 공개 바이너리 배포: 없음' > "$FIXTURE_ROOT/work/README.ko.md"
  else
    printf '%s\n' "- Published binary artifacts: \`$version\`" > "$FIXTURE_ROOT/work/README.md"
    printf '%s\n' "- 공개 바이너리 배포: \`$version\`" > "$FIXTURE_ROOT/work/README.ko.md"
  fi
}

run_check() {
  (
    cd "$FIXTURE_ROOT/work"
    PATH="$FIXTURE_ROOT/bin:$PATH" \
      PTK_RELEASE_FIXTURE="$PTK_RELEASE_FIXTURE" \
      ./check.sh example/ptk
  ) >/dev/null 2>&1
}

cat > "$FIXTURE_ROOT/draft-only.json" <<'EOF'
[{"draft":true,"tag_name":"v0.6.0","published_at":null,"assets":[]}]
EOF
write_readmes none
PTK_RELEASE_FIXTURE="$FIXTURE_ROOT/draft-only.json" run_check

cat > "$FIXTURE_ROOT/public.json" <<'EOF'
[{"draft":false,"tag_name":"v0.6.0","published_at":"2026-08-09T00:00:00Z","assets":[]}]
EOF
write_readmes none
if PTK_RELEASE_FIXTURE="$FIXTURE_ROOT/public.json" run_check; then
  printf 'not ok - public release must invalidate the no-release claim\n' >&2
  exit 1
fi

cat > "$FIXTURE_ROOT/two-releases.json" <<'EOF'
[
  {"draft":false,"tag_name":"v0.6.0","published_at":"2026-08-09T00:00:00Z","assets":[{"name":"PTK-macos-0.6.0-unsigned.dmg"},{"name":"PTK-macos-0.6.0-unsigned.zip"}]},
  {"draft":false,"tag_name":"v0.5.0","published_at":"2026-07-01T00:00:00Z","assets":[{"name":"PTK-macos-0.5.0-unsigned.dmg"},{"name":"PTK-macos-0.5.0-unsigned.zip"}]}
]
EOF
write_readmes 0.5.0
if PTK_RELEASE_FIXTURE="$FIXTURE_ROOT/two-releases.json" run_check; then
  printf 'not ok - an older documented release must not pass\n' >&2
  exit 1
fi

write_readmes 0.6.0
PTK_RELEASE_FIXTURE="$FIXTURE_ROOT/two-releases.json" run_check

printf 'ok - release publication fixture checks\n'
