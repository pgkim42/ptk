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
