# Changelog

All notable PTK changes are tracked here.

## [0.6.0] — Release preparation

This line is not released yet. PTK has no published binary artifacts.

### Port-change notifications

- Prepare opt-in local notifications, disabled by default for new and upgraded
  configurations. On first enable, copy the watched expression only when the
  notification expression is empty; afterward the expressions are independent,
  share the 5,000-port parser limit, and notify only their current intersection.
- Notify only reliable opened and closed transitions. A unique positive PID may
  notify without a process name; ambiguous, failed, or missing listener evidence
  never notifies. Exclude initial, untrusted, transient, and identity-only
  changes.
- Suppress the same port and direction for 10 seconds only after successful
  delivery; allow the opposite direction immediately.
- Passive permission checks at startup, reactivation, Settings presentation,
  and before delivery never prompt. Request macOS permission only after saving
  a valid enabled configuration while status is not determined; route blocked
  access to macOS Settings and retain saved opt-in intent and port selection.
- Open the PTK panel only when a notification is clicked, without adding a
  separate notification history.
- Preserve the Swift-native runtime and existing fail-closed `SIGTERM`-only
  process-termination safety model.

### AI usage

- Add an AI Credits glance for Claude and Codex behind an explicit setting that
  is off by default. Enabling it allows read-only access to existing local
  credentials and 10-minute usage refreshes.
- Honor `CODEX_HOME` for file-backed Codex authentication, distinguish missing
  file support from general sign-out, parse dynamic limit durations, and report
  malformed provider responses accurately.

### Reliability and release preparation

- Keep helper and TCP probe timeouts bounded, classify an empty `lsof` result
  correctly, and preserve the existing confirmation, revalidation, mismatch
  blocking, and `SIGTERM`-only termination policy.
- Preserve Docker bind addresses and protocols, restrict localhost copy actions
  to reachable TCP mappings, and surface `docker ps` failures.
- Make dense panel content scrollable, keep notification permission state fresh
  while notifications are off, and prevent duplicate kill confirmations.
- Build universal Apple Silicon and Intel release artifacts and compare the
  documented publication state with GitHub Releases in CI.

## [0.5.0] — Completed development line

This development line was completed but was not published as a GitHub Release.

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

Run these commands from the repository root for the `0.5.0` development line:

```bash
cd macos && swift test
cd macos && swift build
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
tests/open-source-readiness.sh
tests/release-readiness.sh
```

### Known limitations

- Prepared release artifacts use ad-hoc integrity signing only and have no
  Developer ID signature or notarization.
- Updates are manual; PTK has no update server or in-app updater.
- Scanning is limited to local development ports.
- Service diagnostics are read-only and do not manage containers or databases.
