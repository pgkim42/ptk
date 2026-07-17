# Roadmap

PTK stays small on purpose. The roadmap favors a credible macOS utility and
maintainable open-source project shape over broad feature count.

The current release version is defined by the latest non-Unreleased entry in
`CHANGELOG.md`. This file tracks direction and completion state without serving
as a second version authority.

## v0.5.0 — current release line

Goal: provide a dependable local diagnostic console while keeping the menu bar
surface compact and the service boundary read-only.

Delivered in this line:

- Swift-only native menu bar app with watched-port scanning and manual refresh.
- Editable watched-port profiles and presets for common development stacks.
- Safe process termination with confirmation, immediate revalidation, mismatch
  and ambiguous-listener blocking, and `SIGTERM` only.
- Quick actions for localhost URLs, process details, and open-port summaries.
- Read-only Docker published-port and common local database diagnostics.
- Unsigned DMG and ZIP release artifacts with bilingual installation guidance.
- CI, release-readiness, and public repository policy checks.

Current maintenance priorities:

- Keep scanner results correct across IPv4, IPv6, transient command failures,
  and overlapping refreshes.
- Keep settings edits transactional and refuse to overwrite unreadable stored
  data.
- Keep compact panel controls and diagnostics usable with VoiceOver.
- Preserve existing release artifacts when packaging validation fails.

## Archived planning milestones

The early `v0.1.0`, `v0.2.0`, and `v0.4.0` plans were development milestones.
Their completed work is consolidated into the `0.5.0` changelog and current
release line above instead of remaining as open roadmap work.

## Later considerations

- Signed and notarized distribution when the project can support Developer ID
  requirements.
- Port-change notification polish that remains local and opt-in.
- Manual-only stack bundle/profile-service linking without inferred lifecycle
  actions.

## Out of scope

These are intentionally not planned:

- force kill
- best-effort termination for ambiguous listeners
- Docker container management
- database start, stop, restart, or migration actions
- remote host scanning
- background service orchestration
- automatic profile switching or inferred service lifecycle actions
- Rust, Tauri, Node, or a separate CLI runtime in the active app path