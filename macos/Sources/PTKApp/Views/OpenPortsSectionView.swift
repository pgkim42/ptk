import SwiftUI
import PTKCore

struct OpenPortsSectionView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionHeaderView("포트", trailing: watchedPortsSummary)

            PTKInsetGroup {
                if viewModel.openPorts.isEmpty {
                    EmptyPortsView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.openPorts.enumerated()), id: \.element.port) { index, status in
                                if index > 0 {
                                    PTKHairline()
                                        .padding(.leading, 28)
                                }
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
                                    },
                                    isKillDisabled: viewModel.isTerminatingProcess
                                ) { target in
                                    viewModel.requestKill(target)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var watchedPortsSummary: String {
        "\(viewModel.openPorts.count)/\(viewModel.statuses.count)"
    }
}

enum PortRowMetrics {
    static let regularHeight: CGFloat = 32
    static let diagnosticHeight: CGFloat = 48

    static func height(for status: PortStatus) -> CGFloat {
        status.ptkKillUnavailableReason == nil ? regularHeight : diagnosticHeight
    }
}

private struct EmptyPortsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("열린 감시 포트가 없습니다")
                .font(PTKType.ui(12, weight: .medium))
                .foregroundStyle(PTKTheme.ink)
            Text("감시 중인 수신 포트가 없습니다.")
                .font(PTKType.ui(11))
                .foregroundStyle(PTKTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, PTKSpace.sm)
    }
}
