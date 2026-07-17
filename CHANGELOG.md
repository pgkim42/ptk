# Changelog

All notable PTK changes are tracked here.

## [Unreleased]

- Continue accessibility, settings-safety, scanner-correctness, and release
  packaging improvements without weakening process-termination safeguards.

## [0.5.0]

Current Swift-only macOS release line.

### Added

- Native menu bar port monitoring with manual refresh, saved profiles, common
  development-stack presets, and open/copy localhost actions.
- Read-only service diagnostics for Docker-published ports and common local
  databases.
- Compact change summaries, process details, screenshots, and bilingual
  installation guidance.
- Unsigned DMG and ZIP packaging plus release and repository readiness checks.

### Changed

- Consolidated the active product path on the Swift package under `macos/`.
- Improved panel empty, warning, error, and accessibility states.
- Reduced background scan cadence while the panel is closed.

### Safety

- Process termination remains fail-closed with confirmation, immediate target
  revalidation, mismatch and ambiguous-listener blocking, and `SIGTERM` only.
- Process and scan command execution is asynchronous and lifecycle-safe.

### Verification

Run these commands from the repository root for the `0.5.0` release line:

```bash
cd macos && swift test
cd macos && swift build
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
tests/open-source-readiness.sh
tests/release-readiness.sh
```

### Known limitations

- Release artifacts are unsigned and require the documented first-launch flow.
- Updates are manual; PTK has no update server or in-app updater.
- Scanning is limited to local development ports.
- Service diagnostics are read-only and do not manage containers or databases.
