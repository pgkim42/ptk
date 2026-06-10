# ContentView Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Split the PTK menu bar panel UI from one large `ContentView.swift` file into focused SwiftUI view files without changing runtime behavior.

**Architecture:** `ContentView` remains the top-level panel shell that owns alerts, sheets, background, and vertical layout. Each panel section becomes a small SwiftUI view that receives the existing `PortMonitorViewModel`, so the app state and safety behavior stay untouched. Shared presentational helpers move into tiny view types used by the section files.

**Tech Stack:** SwiftPM, SwiftUI, AppKit-backed macOS menu bar app, existing `PTKCore` domain models.

---

## File Structure

- Modify: `macos/Sources/PTKApp/Views/ContentView.swift`
  - Keep `ContentView`, alerts, settings sheet, panel background, and `PTKTheme`.
  - Remove section-specific private views and helper methods that move to files below.
- Create: `macos/Sources/PTKApp/Views/PanelChromeViews.swift`
  - Add shared `PanelIconButton`, `PanelSectionHeaderView`, `PanelServiceGroupHeaderView`, and `ErrorBannerView`.
- Create: `macos/Sources/PTKApp/Views/PortSummaryHeaderView.swift`
  - Add the top header with app title, open count, and refresh button.
- Create: `macos/Sources/PTKApp/Views/RecentPortChangesView.swift`
  - Add recent port change summary and tooltip.
- Create: `macos/Sources/PTKApp/Views/OpenPortsSectionView.swift`
  - Add open port list and empty state.
- Create: `macos/Sources/PTKApp/Views/ServiceStatusSectionView.swift`
  - Add service status list and Docker container child rows.
- Create: `macos/Sources/PTKApp/Views/PanelFooterView.swift`
  - Add profile quick switch, refresh interval badge, copy, settings, and quit buttons.

No `PTKCore` files should change in this plan.

---

### Task 1: Add Shared Panel Chrome Views

**Files:**
- Create: `macos/Sources/PTKApp/Views/PanelChromeViews.swift`

- [x] **Step 1: Create shared chrome view file**

Add this file:

```swift
import SwiftUI

struct PanelIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 24))
        .help(help)
    }
}

struct PanelSectionHeaderView: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PTKTheme.faint)
                .lineLimit(1)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PTKTheme.faint)
                    .lineLimit(1)
            }
        }
        .frame(height: 12)
    }
}

struct PanelServiceGroupHeaderView: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PTKTheme.faint)
            Spacer()
        }
        .padding(.horizontal, 9)
        .frame(height: 18)
        .background(PTKTheme.card.opacity(0.55))
    }
}

struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PTKTheme.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(PTKTheme.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PTKTheme.orange.opacity(0.12)))
    }
}
```

- [x] **Step 2: Run a narrow compile check**

Run: `cd macos && swift test`

Expected: PASS. The new file is additive and should not affect behavior.

---

### Task 2: Extract Header And Recent Changes

**Files:**
- Create: `macos/Sources/PTKApp/Views/PortSummaryHeaderView.swift`
- Create: `macos/Sources/PTKApp/Views/RecentPortChangesView.swift`

- [x] **Step 1: Create `PortSummaryHeaderView`**

Add this file:

```swift
import SwiftUI

struct PortSummaryHeaderView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("PTK")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)

            Text("Port Toolkit")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)

            Spacer()

            Text(verbatim: "\(viewModel.openPorts.count) OPEN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(viewModel.openPorts.isEmpty ? PTKTheme.faint : PTKTheme.green)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(viewModel.openPorts.isEmpty ? PTKTheme.card : PTKTheme.green.opacity(0.14)))
                .overlay {
                    Capsule().strokeBorder(viewModel.openPorts.isEmpty ? PTKTheme.border : PTKTheme.green.opacity(0.22), lineWidth: 1)
                }

            PanelIconButton(systemName: "arrow.clockwise", help: "새로고침") {
                viewModel.refresh()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .layoutPriority(2)
    }
}
```

- [x] **Step 2: Create `RecentPortChangesView`**

Add this file:

```swift
import SwiftUI
import PTKCore

struct RecentPortChangesView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(PTKTheme.blue)
            Text("최근 변경")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PTKTheme.faint)
            Text(verbatim: recentChangesSummary)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(PTKTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PTKTheme.blue.opacity(0.10)))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(PTKTheme.blue.opacity(0.18), lineWidth: 1)
        }
        .help(recentChangesHelp)
    }

    private var recentChangesSummary: String {
        viewModel.recentPortChanges
            .prefix(2)
            .map(recentChangeDisplayText)
            .joined(separator: "  ·  ")
    }

    private var recentChangesHelp: String {
        viewModel.recentPortChanges
            .map(recentChangeDisplayText)
            .joined(separator: "\n")
    }

    private func recentChangeDisplayText(_ change: PortChange) -> String {
        PortChangePresenter().displayText(for: change)
    }
}
```

- [x] **Step 3: Run a narrow compile check**

Run: `cd macos && swift test`

Expected: PASS.

---

### Task 3: Extract Open Ports And Services Sections

**Files:**
- Create: `macos/Sources/PTKApp/Views/OpenPortsSectionView.swift`
- Create: `macos/Sources/PTKApp/Views/ServiceStatusSectionView.swift`

- [x] **Step 1: Create `OpenPortsSectionView`**

Add this file:

```swift
import SwiftUI
import PTKCore

struct OpenPortsSectionView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSectionHeaderView("Open Ports", trailing: watchedPortsSummary)

            if viewModel.openPorts.isEmpty {
                EmptyPortsView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.openPorts, id: \.port) { status in
                            PortRowView(
                                status: status,
                                onOpen: { status in
                                    viewModel.openLocalhost(for: status)
                                },
                                onCopy: { status in
                                    viewModel.copyLocalhostURL(for: status)
                                },
                                onCopyDetails: { status in
                                    viewModel.copyPortDetails(for: status)
                                }
                            ) { target in
                                viewModel.requestKill(target)
                            }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PTKTheme.table))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PTKTheme.border, lineWidth: 1)
                }
                .frame(height: openPortsListHeight)
            }
        }
    }

    private var watchedPortsSummary: String {
        "\(viewModel.openPorts.count)/\(viewModel.statuses.count)"
    }

    private var openPortsListHeight: CGFloat {
        let rowHeight: CGFloat = 34
        let maxVisibleRows = viewModel.serviceStatuses.isEmpty ? 6 : 4
        let visibleRows = min(max(viewModel.openPorts.count, 1), maxVisibleRows)
        return CGFloat(visibleRows) * rowHeight
    }
}

private struct EmptyPortsView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PTKTheme.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("열린 감시 포트 없음")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PTKTheme.text)
                Text("감시 중인 개발 포트가 조용합니다.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PTKTheme.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PTKTheme.table))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(PTKTheme.border, lineWidth: 1)
        }
    }
}
```

- [x] **Step 2: Create `ServiceStatusSectionView`**

Add this file:

```swift
import SwiftUI
import PTKCore

struct ServiceStatusSectionView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSectionHeaderView("Services", trailing: viewModel.serviceStatusSummary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.groupedServiceStatuses) { group in
                        if viewModel.groupedServiceStatuses.count > 1 {
                            PanelServiceGroupHeaderView(title: group.title)
                        }
                        ForEach(group.statuses, id: \.displayIdentity) { status in
                            ServiceStatusRowView(status: status)
                            if status.group == .builtIn, status.name == "Docker" {
                                ForEach(viewModel.dockerContainerRows) { row in
                                    DockerContainerPortRowView(row: row)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 174)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PTKTheme.table))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PTKTheme.border, lineWidth: 1)
            }
        }
    }
}
```

- [x] **Step 3: Run a narrow compile check**

Run: `cd macos && swift test`

Expected: PASS.

---

### Task 4: Extract Footer And Slim ContentView

**Files:**
- Create: `macos/Sources/PTKApp/Views/PanelFooterView.swift`
- Modify: `macos/Sources/PTKApp/Views/ContentView.swift`

- [x] **Step 1: Create `PanelFooterView`**

Add this file:

```swift
import SwiftUI

struct PanelFooterView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: 8) {
            profileQuickSwitch

            Text(viewModel.refreshInterval.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PTKTheme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(PTKTheme.card))

            Spacer()

            PanelIconButton(systemName: "doc.on.doc", help: "열린 포트 요약 복사") {
                viewModel.copyOpenPortsSummary()
            }

            PanelIconButton(systemName: "gearshape", help: "설정") {
                viewModel.isShowingSettings = true
            }

            PanelIconButton(systemName: "power", help: "종료") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .layoutPriority(2)
    }

    private var profileQuickSwitch: some View {
        Menu {
            ForEach(viewModel.profileOptions) { option in
                Button {
                    do {
                        try viewModel.applyProfileOption(option)
                    } catch {
                        viewModel.errorMessage = "프로필 적용 오류: \(error)"
                    }
                } label: {
                    Text(option.title)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                Text(viewModel.currentProfileTitle)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(PTKTheme.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: 110)
            .background(Capsule().fill(PTKTheme.card))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("감시 포트 프로필 빠른 전환")
    }
}
```

- [x] **Step 2: Replace section bodies in `ContentView`**

Edit `ContentView.body` so the top-level layout uses the extracted views:

```swift
VStack(spacing: 0) {
    PortSummaryHeaderView(viewModel: viewModel)

    Divider().overlay(PTKTheme.border)

    VStack(spacing: 10) {
        if let errorMessage = viewModel.errorMessage {
            ErrorBannerView(message: errorMessage)
        }

        if !viewModel.recentPortChanges.isEmpty {
            RecentPortChangesView(viewModel: viewModel)
        }

        OpenPortsSectionView(viewModel: viewModel)

        if !viewModel.serviceStatuses.isEmpty {
            ServiceStatusSectionView(viewModel: viewModel)
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .layoutPriority(1)

    Divider().overlay(PTKTheme.border)

    PanelFooterView(viewModel: viewModel)
}
```

Remove the old private members from `ContentView.swift`:

```swift
header
portSection
openPortsListHeight
serviceSection
footer
profileQuickSwitch
sectionHeader(_:trailing:)
serviceGroupHeader(_:)
errorBanner(_:)
recentChangesBanner
recentChangesSummary
recentChangesHelp
recentChangeDisplayText(_:)
watchedPortsSummary
serviceSummary
iconButton(_:help:action:)
EmptyPortsView
```

Keep `ContentView.panelSize`, `viewModel`, the alert modifiers, the sheet modifier,
and `PTKTheme` in `ContentView.swift`.

- [x] **Step 3: Run tests**

Run: `cd macos && swift test`

Expected: PASS.

- [x] **Step 4: Check diff scope**

Run:

```sh
git diff --stat
git diff --name-only
git diff --check
```

Expected:

- Changed files are in `macos/Sources/PTKApp/Views/` plus this plan document.
- No `macos/Sources/PTKCore/Features/PortMonitor/Services/ProcessKiller.swift` change.
- No whitespace errors.

- [x] **Step 5: Commit implementation**

Run:

```sh
git add macos/Sources/PTKApp/Views docs/superpowers/plans/2026-06-10-content-view-refactor.md
git commit -m "refactor(app): 패널 뷰 구조 분리" \
  -m "ContentView에 모여 있던 패널 섹션을 작은 SwiftUI 뷰로 나눴다." \
  -m "포트 스캔과 프로세스 종료 안전 로직은 변경하지 않았다." \
  -m "Tested: cd macos && swift test"
```

---

## Self-Review

- Spec coverage: the plan extracts all five requested section views and keeps
  `ContentView` as the panel shell.
- Scope check: all implementation files are under `PTKApp/Views`; no core port
  scan, process lookup, kill, or service monitor logic is planned for change.
- Ambiguity check: extracted views share the existing `PortMonitorViewModel`,
  matching the design choice to avoid model/data-flow changes in the first pass.
- Verification: the plan includes `swift test`, diff scope checks, and
  whitespace checks before the implementation commit.
