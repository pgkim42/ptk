import SwiftUI
import PTKCore

struct ServiceStatusSectionView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionHeaderView("서비스", trailing: viewModel.serviceStatusSummary)

            PTKInsetGroup {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.groupedServiceStatuses) { group in
                            if viewModel.showsServiceGroupHeaders {
                                PanelServiceGroupHeaderView(title: group.title)
                            }
                            ForEach(Array(group.statuses.enumerated()), id: \.element.displayIdentity) { index, status in
                                if index > 0 || viewModel.showsServiceGroupHeaders {
                                    PTKHairline()
                                        .padding(.leading, 28)
                                }
                                ServiceStatusRowView(status: status)
                                if status.group == .builtIn, status.kind == .dockerDaemon {
                                    ForEach(viewModel.dockerContainerRows) { row in
                                        DockerContainerPortRowView(
                                            row: row,
                                            onCopyURL: { viewModel.copyDockerContainerURL(for: row) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

enum ServiceStatusListMetrics {
    static let groupHeaderHeight: CGFloat = 20
    static let statusRowHeight: CGFloat = 28
    static let minimumHeight = groupHeaderHeight + statusRowHeight
    static let maximumHeight: CGFloat = 168
}
