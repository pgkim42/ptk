# PTK

[한국어 README](README.ko.md)

PTK is a native macOS menu bar utility for keeping a local development machine readable and under control.

The first tool in PTK is a **local port monitor**. It watches a configurable set of development ports, shows which ones are currently listening, identifies the owning process when possible, and lets you terminate only the processes that can be verified safely.

PTK is currently a Swift-only macOS app. The old Rust/Tauri/Node runtime has been removed from the active product path; the app now builds and runs from the Swift Package under `macos/`.

## Status

- Platform: macOS 13+
- Runtime: Swift, AppKit, SwiftUI
- Entry point: `macos/`
- UI surface: menu bar status item with a compact utility panel
- Distribution: local development build only for now
- Scope: personal tool, maintained as a public repository

## What It Does

### Port Monitoring

PTK periodically scans the configured port expression and shows only the watched ports that are currently open.

The menu bar title shows the open watched-port count, such as `PTK 0` or `PTK 2`.

The panel can show:

- open watched-port count
- open port number
- PID, when exactly one listener can be identified
- process name, when available
- kill action only when the target is safe
- parse or lookup errors without hiding the rest of the panel

### Service Status

PTK also shows read-only status for common local development services:

| Service | Check |
| --- | --- |
| Docker | Docker daemon availability |
| PostgreSQL | port `5432` |
| MySQL | port `3306` |
| Redis | port `6379` |
| MongoDB | port `27017` |

These rows are status indicators only. PTK does not start, stop, restart, or manage Docker containers or database services.

### Safe Process Termination

PTK is intentionally conservative because killing a local process is destructive.

A kill action is available only when all of these are true:

1. The watched port is open.
2. Exactly one listener PID is known.
3. The process name is known.
4. The user confirms the native macOS confirmation alert.
5. Right before termination, PTK re-checks the port, PID, and process name.

If any of those checks fail, PTK blocks the kill. Ambiguous same-port listeners are left open but non-killable.

PTK sends `SIGTERM` only. It does not provide force kill, mismatch override, or best-effort termination for ambiguous listeners.

### Settings

The settings sheet supports:

- watched port expression editing
- validation before saving
- refresh interval selection: `1s`, `3s`, `5s`, `10s`
- theme selection: system, light, dark
- persistence through `UserDefaults`

## Default Watched Ports

The default profile targets common local development servers:

| Range | Typical use |
| --- | --- |
| `3000-3009` | Next.js and similar dev servers |
| `5173-5182` | Vite dev servers |
| `4200-4209` | Angular dev servers |
| `8080-8089` | Spring Boot and similar backend servers |

Default expression:

```text
3000-3009,5173-5182,4200-4209,8080-8089
```

When changing the default profile, keep these files in sync:

- `README.md`
- `README.ko.md`
- `macos/Sources/PTKCore/Features/PortMonitor/Domain/AppDefaults.swift`
- related tests under `macos/Tests/PTKCoreTests/Features/PortMonitor/`

## Run

PTK is not packaged as an installer yet. Run it from the Swift package:

```bash
cd macos
swift run PTK
```

After launch, PTK appears in the macOS menu bar instead of opening a normal app window.

## Development

From the repository root:

```bash
cd macos && swift test
cd macos && swift build
cd macos && swift run PTK
```

For the Xcode scheme test path:

```bash
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

## Project Layout

```text
macos/
├── Package.swift
├── Sources/
│   ├── PTK/
│   │   └── executable entry point
│   ├── PTKApp/
│   │   ├── AppKit menu bar shell
│   │   ├── SwiftUI views
│   │   └── app-facing view model
│   └── PTKCore/
│       ├── Shell/
│       │   └── refresh scheduling
│       └── Features/
│           ├── PortMonitor/
│           │   ├── Domain/      # port expressions, menu model, port state
│           │   ├── Services/    # lsof/ps lookup, scan, kill safety
│           │   └── Settings/    # UserDefaults-backed settings
│           └── ServiceMonitor/
│               └── Services/    # Docker and local DB status checks
└── Tests/
    ├── PTKAppTests/
    └── PTKCoreTests/
```

## Design Principles

- Keep the runtime native: Swift, AppKit, and SwiftUI.
- Keep feature logic testable in `PTKCore`.
- Keep the menu bar surface compact and quick to scan.
- Treat process termination as fail-closed.
- Always confirm before killing.
- Always revalidate immediately before killing.
- Send `SIGTERM` only.
- Keep service status read-only.
- Do not add Rust, Tauri, Node, or a separate CLI runtime back into the app path.

## Testing Strategy

Tests do not terminate real processes. Kill behavior is covered with fake resolvers and fake terminators.

Current test coverage focuses on:

- port expression parsing
- default watched-port stability
- open-port filtering and sorting
- ambiguous listener handling
- kill confirmation and revalidation
- PID/process mismatch blocking
- refresh scheduling
- settings persistence and validation
- Docker and database status classification
- service command timeout handling
- app view model behavior

## Not In Scope Yet

PTK currently does not provide:

- installer packaging
- launch-at-login support
- notifications
- Docker container management
- database health queries
- remote host scanning
- force kill
- background service orchestration

## Public Repository Notes

This repository is intended to remain safe for public use.

- Do not commit API keys, tokens, passwords, private keys, or personal machine secrets.
- Keep local agent state such as `.omo/` and `.omx/` ignored.
- Prefer local settings or ignored files for machine-specific values.
- Avoid documenting private infrastructure or account details.

## License

No license file has been added yet. Add a `LICENSE` before treating PTK as reusable open-source software.
