# Roadmap

PTK stays small on purpose. The roadmap favors a credible macOS utility and
maintainable open-source project shape over broad feature count.

The current preparation target is `0.1.0`, as named in the versioned release
preparation entry in `CHANGELOG.md`. This file tracks direction and completion
state without serving as a second version authority. PTK has no published binary
release yet.

## v0.1.0 — current release preparation

Goal: keep a bounded local port-change notification without changing PTK's
Swift-native runtime or process-termination safety boundary. This line is not
released, and no binary artifact is published.

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
- Native menu bar port monitoring with watched-port scanning and manual refresh.
- Unsigned DMG and ZIP release artifacts.
- Universal Apple Silicon and Intel release packaging, with publication
  metadata verified in CI.
- Tag-triggered packaging that uploads unsigned DMG and ZIP files to a
  draft GitHub Release without publishing it. The current `0.1.0`
  heading remains a preparation label, not a tag to push.

Current maintenance priorities:

- Keep scanner results correct across IPv4, IPv6, transient command failures,
  and overlapping refreshes.
- Keep settings edits transactional and refuse to overwrite unreadable stored
  data.
- Keep compact panel controls and diagnostics usable with VoiceOver.
- Preserve existing release artifacts when packaging validation fails.

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
