import SwiftUI
import PTKCore

struct ContentView: View {
    static let panelSize = NSSize(width: 392, height: 420)

    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
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
