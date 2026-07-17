# Roadmap

PTK stays small on purpose. The roadmap favors a credible macOS utility and
maintainable open-source project shape over broad feature count.

The current preparation target is `0.6.0`, as named in the versioned release
preparation entry in `CHANGELOG.md`. This file tracks direction and completion
state without serving as a second version authority; `0.5.0` remains the latest
published release.

## v0.6.0 — current release preparation

Goal: add a bounded, local port-change notification without changing PTK's
Swift-native runtime or process-termination safety boundary. This line is not
released; `0.5.0` remains the latest published artifact.

Release preparation scope:

- Default notifications to off for new and upgraded configurations. On first
  enable, copy the watched expression only when the notification expression is
  empty; afterward the expressions are independent, share the 5,000-port parser
  limit, and notify only their current intersection.
- Notify only reliable opened and closed transitions. A unique positive PID may
  notify without a process name; ambiguous, failed, or missing listener evidence
  never notifies. Exclude initial, untrusted, transient, and identity-only
  changes.
- After successful delivery, suppress the same port and direction for 10
  seconds while allowing the opposite direction immediately.
- Passive permission checks at startup, reactivation, Settings presentation,
  and before delivery never prompt. Request macOS permission only after saving
  a valid enabled configuration while status is not determined; route blocked
  access to macOS Settings and preserve saved opt-in intent when permission is
  denied or blocked.
- Open the PTK panel only from a notification click and keep no separate
  notification history.
- Preserve `SIGTERM`-only, fail-closed termination and the Swift-only native
  runtime.

## v0.5.0 — previous release line

Delivered in that line:

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
Their completed work is consolidated into the `0.5.0` changelog and previous
release line above instead of remaining as open roadmap work.

## Later considerations

- Signed and notarized distribution when the project can support Developer ID
  requirements.
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