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
