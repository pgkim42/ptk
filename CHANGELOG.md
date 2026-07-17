# Changelog

All notable PTK changes are tracked here.

## [0.6.0] — Release preparation

This line is not released yet; `0.5.0` remains the latest published artifact.

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

## [0.5.0]

Latest published Swift-only macOS release line.

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
