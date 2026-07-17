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
        let maxVisibleRows = viewModel.serviceStatuses.isEmpty ? 6 : 4
        return OpenPortsListMetrics.height(
            for: viewModel.openPorts,
            maxVisibleRows: maxVisibleRows
        )
    }
}

enum PortRowMetrics {
    static let regularHeight: CGFloat = 34
    static let diagnosticHeight: CGFloat = 44

    static func height(for status: PortStatus) -> CGFloat {
        status.ptkKillUnavailableReason == nil ? regularHeight : diagnosticHeight
    }
}

enum OpenPortsListMetrics {
    static func height(for statuses: [PortStatus], maxVisibleRows: Int) -> CGFloat {
        statuses
            .prefix(max(maxVisibleRows, 1))
            .reduce(0) { $0 + PortRowMetrics.height(for: $1) }
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
