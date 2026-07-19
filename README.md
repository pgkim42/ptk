# PTK

A native macOS menu bar utility for safely inspecting and cleaning local development ports.

![CI](https://github.com/pgkim42/ptk/actions/workflows/ci.yml/badge.svg)
![License: 0BSD](https://img.shields.io/badge/license-0BSD-blue.svg)

[한국어 README](README.ko.md)

![PTK menu bar panel](docs/assets/ptk-panel.png)

PTK keeps a local development machine readable without turning into a service
orchestrator. It watches common development ports, shows the verified listener
details it can safely identify, and keeps destructive process termination behind
a fail-closed safety model.

The first tool in PTK is a **local port monitor** with a read-only local services glance. It watches a configurable set of development ports, shows which ones are currently listening, identifies the owning process when possible, surfaces Docker-published container ports, and lets you terminate only the processes that can be verified safely.

PTK is currently a Swift-only macOS app. The old Rust/Tauri/Node runtime has been removed from the active product path; the app now builds and runs from the Swift Package under `macos/`.

## Why PTK?

Local development often leaves behind ports that are hard to reason about:
Next.js, Vite, backend servers, database services, and old test processes can
all compete for the same machine. Killing the wrong PID is worse than leaving a
port alone, so PTK prefers a small native surface that makes the current state
obvious and only enables process termination when the target can be revalidated.

The project is intentionally narrow: inspect local development ports, expose the
common cleanup action, and document the safety boundary clearly enough that the
tool stays trustworthy as it grows.

## Status

- Current release preparation: `0.6.0` (not yet released)
- Latest published artifacts: `0.5.0`
- Platform: macOS 13+
- Runtime: Swift, AppKit, SwiftUI
- Entry point: `macos/`
- UI surface: menu bar status item with a compact utility panel
- Distribution: unsigned manual release artifacts for GitHub Releases
- Scope: personal tool, maintained as a public open-source repository
- License: `0BSD` (`SPDX-License-Identifier: 0BSD`)

`CHANGELOG.md` distinguishes the current release preparation from published
artifacts. The `0.5.0` artifact names below remain the latest downloadable
release until `0.6.0` is published.

PTK is distributed as unsigned manual release artifacts for now. It does not
use paid Developer ID signing, notarization, App Store distribution, Sparkle, or
an update server yet.

## Project Health

- CI runs Swift package tests, Swift build, release readiness, and repository
  readiness checks.
- `CONTRIBUTING.md` documents verification commands and the process-termination
  safety boundary.
- `SECURITY.md` covers private reporting and safe handling of machine-specific
  details.
- `docs/roadmap.md` tracks release preparation and maintenance priorities.
- The app runtime is Swift-only; Rust, Tauri, Node, and separate CLI runtimes
  are intentionally kept out of the active product path.

## What It Does

### Port Monitoring

PTK periodically scans the configured port expression and shows only the watched ports that are currently open.

The menu bar status item shows a network icon with the open watched-port count, such as `0` or `2`, while its tooltip keeps the PTK name and open-port summary.

The panel can show:

- open watched-port count
- open port number without locale grouping
- PID without locale grouping, when exactly one listener can be identified
- short process executable name in the row, when available
- full process path or command in copied details and hover help when available
- quick actions for opening or copying a localhost URL
- kill action only when the target is safe
- parse or lookup errors without hiding the rest of the panel
- quick profile switching for saved watched-port profiles
- kill-unavailable explanations with next-check hints
- read-only Docker published-port child rows in the Services section

### Panel Language and Accessibility

The current app interface uses consistent Korean labels for port actions,
service groups, and service states. For example, local-address actions use the
same wording in hover help and VoiceOver labels, and service badges use
`실행 중`, `중지됨`, and `확인 불가`.

The menu bar item exposes an accessible summary of the open watched-port count.
Panel icon buttons have explicit labels and action hints, port diagnostics are
read as a single explanation, and service rows combine the service name, detail,
and state into one VoiceOver label. Decorative status indicators are excluded
when they would only repeat nearby text. Settings controls for notifications
also expose labels, hints, validation errors, permission status, and the macOS
Settings action.

### Port-Change Notifications

`0.6.0` release preparation adds an opt-in local notification for selected
ports. It is off by default for new and upgraded configurations. On first
enable, PTK copies the watched expression only when the notification expression
is empty; the expressions are independent afterward. They share the
comma-and-range grammar and 5,000-port parser limit, for example
`3000,5173-5182`, and a port must be in their current intersection to notify.

PTK notifies only reliable open and closed transitions. A unique positive PID
is reliable even when its process name is unavailable; ambiguous, failed, or
missing listener evidence never notifies. It does not notify for the initial
scan, untrusted or transient observations, or identity-only changes. After a
successful delivery, the same port and direction are suppressed for 10 seconds;
the opposite direction remains immediate. Notifications have no separate
history.

Passive permission checks at startup, reactivation, Settings presentation, and
before delivery never prompt. macOS permission may be requested only after a
valid enabled configuration is saved while its status is not determined. PTK
routes blocked permission to macOS Settings. A denied or blocked permission
does not erase the saved opt-in intent or selected expression. Clicking a
notification opens the PTK panel only.

### Service Status

PTK also shows read-only status for common local development services:

| Service | Check |
| --- | --- |
| Docker | Docker daemon availability and published container ports |
| PostgreSQL | port `5432` |
| MySQL | port `3306` |
| Redis | port `6379` |
| MongoDB | port `27017` |

These rows are status indicators only. PTK does not start, stop, restart, or
manage Docker containers or database services. Additional read-only service port
checks can be saved in settings for tools such as RabbitMQ, Elasticsearch,
MinIO, or LocalStack.

When Docker is running, PTK also shows child rows under the Docker service row
for running containers with host-published ports. The display is always
`host -> container`, such as `3000 -> 80` or `4000 -> 4000`. A single numeric
host port can be copied as `http://localhost:<port>` from the Docker child row.
Range, hidden, summary, invalid, or ambiguous multi-port rows do not expose a
copy action. Containers without published host ports are hidden, and Docker
child rows are not included in the Services running/total counter.

Custom service checks remain read-only and are visually grouped separately from
built-in services. When no custom services are saved, the compact panel shows a
short help row that points to Settings without adding a panel-side mutation
action.

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

When a kill action is blocked, PTK explains the reason, such as ambiguous
listeners, missing PID/process metadata, or a revalidation mismatch, and keeps
the unsafe action unavailable.

### Settings

![PTK settings sheet](docs/assets/ptk-settings.png)

The settings sheet supports:

- watched port expression editing
- port presets for common local development stacks
- validation before saving
- named watched-port profiles
- custom read-only service port checks
- refresh interval selection: `1s`, `3s`, `5s`, `10s`
- theme selection: system, light, dark
- persistence through `UserDefaults`
- quick switching for saved watched-port profiles
- port-change notifications: opt-in switch, selected-port expression, and macOS permission status

### Port Presets and Quick Actions

The settings sheet includes validated port presets:

| Preset | Expression |
| --- | --- |
| Full Stack | `3000-3009,5173-5182,4200-4209,8080-8089` |
| Frontend | `3000-3009,5173-5182` |
| API | `8000-8009,8080-8089` |
| Data | `3306,5432,6379,27017` |

Open port rows include quick actions to open `http://localhost:<port>` in the
browser, copy that localhost URL, or copy port details such as PID, process path
or command, and kill-unavailable reasons. The row itself stays compact by showing
the executable name first, and the footer can copy a compact summary of currently
open watched ports.

When the panel is closed, PTK reduces scan cadence with an internal quiet
interval that is slower than every user-selectable refresh interval. Reopening
the panel restores the selected interval and refreshes immediately.

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

## Install

Download `PTK-macos-0.5.0-unsigned.dmg` from GitHub Releases.

1. Open the DMG.
2. Drag `PTK.app` to `Applications`.
3. Open `Applications`.
4. Right-click PTK.app and choose **Open**.
5. Confirm **Open** when macOS shows the unsigned app warning.

This release is unsigned. macOS may block the first launch because it cannot
verify the developer. The right-click **Open** flow is required only when
Gatekeeper blocks the normal double-click launch.

PTK appears in the macOS menu bar after launch instead of opening a normal app
window.

PTK also publishes `PTK-macos-0.5.0-unsigned.zip` for users who prefer a plain
archive. Unzip it, move `PTK.app` to `/Applications`, then use the same first
launch flow.

### Manual Updates

PTK does not include automatic updates yet. To update, download the latest
GitHub Release, quit PTK, and replace the app manually in `/Applications`.

## Run From Source

Developers can still run PTK from the Swift package:

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

Repository metadata can be checked with:

```bash
tests/open-source-readiness.sh
```

Release preparation and project management checks can be run with:

```bash
tests/release-readiness.sh
tests/package-readiness.sh
tests/github-management-readiness.sh
```

See `CHANGELOG.md` for release notes and `docs/roadmap.md` for the current
release roadmap.

## Contributing

See `CONTRIBUTING.md` for contribution guidelines, verification commands, and
the project safety boundaries.

Use GitHub issues for bug reports and feature requests. If a report includes
private machine details, follow `SECURITY.md` and do not post secrets publicly.

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
│               └── Services/    # Docker ports and local DB status checks
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
- Docker published-port parsing and read-only child rows
- service command timeout handling
- app view model behavior
- notification reliable transitions, consent and permission, delivery
  suppression, and click routing

## Not In Scope Yet

PTK currently does not provide:

- signed PKG installer packaging
- launch-at-login support
- Docker container management
- database health queries
- remote host scanning
- force kill
- background service orchestration

## Public Repository Notes

This repository is intended to remain safe for public use.

- Do not commit API keys, tokens, passwords, private keys, or personal machine secrets.
- Keep local agent state such as `.gjc/`, `.omo/`, and `.omx/` ignored.
- Prefer local settings or ignored files for machine-specific values.
- Avoid documenting private infrastructure or account details.

## License

PTK is distributed under the `0BSD` license. See `LICENSE`.
