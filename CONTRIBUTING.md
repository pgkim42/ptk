# Contributing

PTK is a personal macOS menu bar tool maintained in public. Contributions are
welcome when they keep the app small, native, and safe around local process
termination.

## Development Setup

PTK builds from the Swift Package under `macos/`.

```bash
cd macos && swift test
cd macos && swift build
cd macos && swift run PTK
```

For the Xcode scheme path:

```bash
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

## Contribution Guidelines

- Keep changes narrow and repo-consistent.
- Keep runtime code Swift-only.
- Do not add Rust, Tauri, Node, or a separate CLI runtime to the app path.
- Keep feature logic testable in `PTKCore`.
- Keep service status read-only.
- Do not start, stop, or restart Docker or database services from PTK.
- Preserve process termination safety: confirmation, immediate revalidation,
  mismatch blocking, and SIGTERM only.
- Do not add force-kill, override, or best-effort kill behavior for ambiguous
  listeners.

## Tests

Run the Swift checks before opening a pull request:

```bash
cd macos && swift test
cd macos && swift build
```

If a change touches app shell behavior, also run:

```bash
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

Documentation and repository metadata can be checked with:

```bash
tests/open-source-readiness.sh
```

## Default Watched Ports

When changing the default watched-port profile, update these together:

- `README.md`
- `README.ko.md`
- `macos/Sources/PTKCore/Features/PortMonitor/Domain/AppDefaults.swift`
- related tests under `macos/Tests/PTKCoreTests/Features/PortMonitor/`

## Commit Messages

Follow `docs/commit-rules.md`: Conventional Commits prefix in English, Korean
subject and body, and the 50/72 line-length rule.
