# Roadmap

PTK stays small on purpose. The roadmap favors a credible macOS utility and
maintainable open-source project shape over broad feature count.

## v0.1.0

Goal: ship the first public Swift-only macOS menu bar release.

- Release packaging: Unsigned DMG and ZIP release artifacts.
  (implemented in development)
- Add a README screenshot or short demo GIF.
- Prepare release notes with the exact verification commands.
- Confirm CI covers Swift tests, Swift build, Xcode scheme tests, and repository
  metadata checks.
- Keep process termination fail-closed: confirmation, revalidation, mismatch
  blocking, ambiguous-listener blocking, and `SIGTERM` only.

## v0.2.0

Goal: improve day-to-day local development ergonomics without expanding PTK
into a service orchestrator.

- Manual refresh action in the menu bar panel. (implemented in development)
- Watched-port presets for common development stacks. (implemented in development)
- Quick actions to open or copy localhost URLs and open-port summaries.
  (implemented in development)
- Better process details for verified listeners, such as copyable PID or
  command text when safe to show.
- Small menu bar polish for empty, warning, and error states.

## v0.4.0

Goal: make PTK feel like a small local diagnostic console while keeping the
menu bar surface compact and read-only service boundary intact.

- Quick switching for saved watched-port profiles.
- Read-only custom service grouping and labels.
- Clear kill-unavailable explanations for ambiguous, missing, or mismatched
  process lookup states.
- Panel-open normal refresh and panel-closed quiet refresh, where quiet cadence
  stays slower than every user-selectable refresh interval.
- Keep the same non-goals: no unsafe kill overrides, no service lifecycle
  management, no automatic profile switching, and no new dashboard window.

## Out of scope

These are intentionally not planned for the early roadmap:

- force kill
- best-effort termination for ambiguous listeners
- Docker container management
- database start, stop, restart, or migration actions
- remote host scanning
- background service orchestration
- Rust, Tauri, Node, or a separate CLI runtime in the active app path
