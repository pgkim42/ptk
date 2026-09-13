import SwiftUI
import PTKCore

struct ContentView: View {
    static let panelSize = NSSize(width: 392, height: 528)

    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isShowingSettings {
                SettingsSheetView(viewModel: viewModel) {
                    viewModel.isShowingSettings = false
                }
            } else {
                monitor
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .foregroundStyle(PTKTheme.ink)
        .background(PTKTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: PTKTheme.radiusPanel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PTKTheme.radiusPanel, style: .continuous)
                .strokeBorder(PTKTheme.rule, lineWidth: 1)
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
            "종료 결과 확인",
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
        .preferredColorScheme(viewModel.theme.preferredColorScheme)
    }

    private var monitor: some View {
        VStack(spacing: 0) {
            PortSummaryHeaderView(viewModel: viewModel)
            PTKHairline()

            VStack(alignment: .leading, spacing: PTKSpace.sm) {
                if let message = viewModel.killStatusMessage {
                    HStack(spacing: PTKSpace.sm) {
                        if viewModel.isTerminatingProcess {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text(message).font(PTKType.ui(12))
                    }
                    .accessibilityElement(children: .combine)
                }

                if let errorMessage = viewModel.errorMessage {
                    ErrorBannerView(message: errorMessage)
                }

                if !viewModel.recentPortChanges.isEmpty {
                    RecentPortChangesView(viewModel: viewModel)
                }

                OpenPortsSectionView(viewModel: viewModel)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)

                if !viewModel.serviceStatuses.isEmpty {
                    ServiceStatusSectionView(viewModel: viewModel)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .layoutPriority(1)
                }
            }
            .padding(PTKSpace.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            PTKHairline()
            PanelFooterView(viewModel: viewModel)
        }
    }
}
