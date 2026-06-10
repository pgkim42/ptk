import SwiftUI
import PTKCore

struct ContentView: View {
    static let panelSize = NSSize(width: 392, height: 420)

    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(PTKTheme.border)

            VStack(spacing: 10) {
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }

                if !viewModel.recentPortChanges.isEmpty {
                    recentChangesBanner
                }

                portSection

                if !viewModel.serviceStatuses.isEmpty {
                    serviceSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)

            Divider().overlay(PTKTheme.border)

            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .foregroundStyle(PTKTheme.text)
        .background {
            ZStack {
                PTKTheme.panel
                LinearGradient(
                    colors: [PTKTheme.panelTop, PTKTheme.panel],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PTKTheme.border, lineWidth: 1)
        }
        .alert(
            "프로세스를 종료할까요?",
            isPresented: .init(
                get: { viewModel.killConfirmationTarget != nil },
                set: { if !$0 { viewModel.cancelKill() } }
            ),
            presenting: viewModel.killConfirmationTarget
        ) { target in
            Button("종료", role: .destructive) {
                viewModel.confirmKill()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelKill()
            }
        } message: { target in
            Text(verbatim: "Port \(target.port), PID \(target.pid), \(target.processName)를 종료합니다.")
        }
        .alert(
            "종료 실패",
            isPresented: .init(
                get: { viewModel.killErrorMessage != nil },
                set: { if !$0 { viewModel.killErrorMessage = nil } }
            ),
            presenting: viewModel.killErrorMessage
        ) { message in
            Button("확인") {
                viewModel.killErrorMessage = nil
            }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $viewModel.isShowingSettings) {
            SettingsSheetView(viewModel: viewModel) {
                viewModel.isShowingSettings = false
            }
        }
        .preferredColorScheme(viewModel.theme.preferredColorScheme)
    }

    private var header: some View {
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

            iconButton("arrow.clockwise", help: "새로고침") {
                viewModel.refresh()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .layoutPriority(2)
    }

    private var portSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Open Ports", trailing: watchedPortsSummary)

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

    private var openPortsListHeight: CGFloat {
        let rowHeight: CGFloat = 34
        let maxVisibleRows = viewModel.serviceStatuses.isEmpty ? 6 : 4
        let visibleRows = min(max(viewModel.openPorts.count, 1), maxVisibleRows)
        return CGFloat(visibleRows) * rowHeight
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Services", trailing: serviceSummary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.groupedServiceStatuses) { group in
                        if viewModel.groupedServiceStatuses.count > 1 {
                            serviceGroupHeader(group.title)
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

    private var footer: some View {
        HStack(spacing: 8) {
            profileQuickSwitch

            Text(viewModel.refreshInterval.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PTKTheme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(PTKTheme.card))

            Spacer()

            iconButton("doc.on.doc", help: "열린 포트 요약 복사") {
                viewModel.copyOpenPortsSummary()
            }

            iconButton("gearshape", help: "설정") {
                viewModel.isShowingSettings = true
            }

            iconButton("power", help: "종료") {
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


    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
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

    private func serviceGroupHeader(_ title: String) -> some View {
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

    private func errorBanner(_ message: String) -> some View {
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

    private var recentChangesBanner: some View {
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

    private var watchedPortsSummary: String {
        "\(viewModel.openPorts.count)/\(viewModel.statuses.count)"
    }

    private var serviceSummary: String {
        viewModel.serviceStatusSummary
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 24))
        .help(help)
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

enum PTKTheme {
    static let panel = adaptive(
        light: color(red: 0.94, green: 0.96, blue: 0.98),
        dark: color(red: 0.07, green: 0.08, blue: 0.10)
    )
    static let panelTop = adaptive(
        light: color(red: 1.00, green: 1.00, blue: 1.00),
        dark: color(red: 0.12, green: 0.13, blue: 0.16)
    )
    static let table = adaptive(
        light: color(white: 0.0, alpha: 0.045),
        dark: color(white: 1.0, alpha: 0.048)
    )
    static let card = adaptive(
        light: color(white: 0.0, alpha: 0.055),
        dark: color(white: 1.0, alpha: 0.06)
    )
    static let border = adaptive(
        light: color(white: 0.0, alpha: 0.10),
        dark: color(white: 1.0, alpha: 0.075)
    )
    static let text = adaptive(
        light: color(white: 0.06, alpha: 0.92),
        dark: color(white: 1.0, alpha: 0.92)
    )
    static let muted = adaptive(
        light: color(white: 0.12, alpha: 0.58),
        dark: color(white: 1.0, alpha: 0.58)
    )
    static let faint = adaptive(
        light: color(white: 0.12, alpha: 0.42),
        dark: color(white: 1.0, alpha: 0.42)
    )
    static let green = Color(red: 0.32, green: 0.86, blue: 0.50)
    static let red = Color(red: 0.92, green: 0.34, blue: 0.36)
    static let orange = Color(red: 1.00, green: 0.68, blue: 0.28)
    static let blue = Color(red: 0.36, green: 0.62, blue: 1.00)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func color(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func color(white: CGFloat, alpha: CGFloat) -> NSColor {
        NSColor(calibratedWhite: white, alpha: alpha)
    }
}
