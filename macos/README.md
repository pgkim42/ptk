# PTK macOS Swift app

This directory contains the native macOS Swift migration target for PTK.
The first implementation uses a Swift Package with an AppKit `NSStatusItem`
menu-bar executable and a separate testable `PTKCore` module. This keeps the
menu-bar app buildable with copy-paste-safe SwiftPM and Xcode commands while
leaving the old Tauri/Rust stack untouched as a behavioral reference.

## Scaffold decision

- Project shape: Swift Package under `macos/` with executable app target
  `PTKApp`, library target `PTKCore`, and test target `PTKCoreTests`.
- UI shell direction: AppKit `NSStatusItem`.
- Deployment target: macOS 13 or newer.
- Runtime boundary: the Swift app must not call or embed the Rust/Tauri core.

## Build and test

From the repository root:

```bash
cd macos && swift test
cd macos && swift build
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

The executable product is named `PTK`.
