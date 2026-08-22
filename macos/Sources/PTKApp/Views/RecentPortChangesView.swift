import SwiftUI
import PTKCore

struct RecentPortChangesView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            PTKSectionLabel(title: "최근")

            PTKInsetGroup {
                VStack(spacing: 0) {
                    ForEach(Array(visibleChanges.enumerated()), id: \.element.id) { index, change in
                        if index > 0 {
                            PTKHairline()
                                .padding(.leading, PTKSpace.sm)
                        }
                        let displayData = recentChangeDisplayData(change, relativeTo: now)
                        HStack(spacing: 8) {
                            Text(displayData.primaryText)
                                .font(PTKType.mono(11))
                                .foregroundStyle(PTKTheme.ink)
                                .lineLimit(1)
                            if let detailText = displayData.detailText {
                                Text(detailText)
                                    .font(PTKType.mono(11))
                                    .foregroundStyle(PTKTheme.faint)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Text(displayData.timeText)
                                .font(PTKType.ui(10))
                                .foregroundStyle(PTKTheme.faint)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, PTKSpace.sm)
                        .frame(height: 24)
                        .accessibilityLabel(displayData.accessibilityText)
                        .help(displayData.helpText)
                    }
                }
            }
        }
        .help(recentChangesHelp(relativeTo: now))
    }

    private var visibleChanges: ArraySlice<PortChange> {
        viewModel.recentPortChanges.prefix(3)
    }

    private func recentChangesHelp(relativeTo now: Date) -> String {
        visibleChanges
            .map { recentChangeDisplayData($0, relativeTo: now).helpText }
            .joined(separator: "\n")
    }

    private func recentChangeDisplayData(_ change: PortChange, relativeTo now: Date) -> RecentPortChangeDisplayData {
        PortChangePresenter().displayData(for: change, relativeTo: now)
    }
}
