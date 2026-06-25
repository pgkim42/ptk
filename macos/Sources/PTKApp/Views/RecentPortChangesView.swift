import SwiftUI
import PTKCore

struct RecentPortChangesView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(PTKTheme.blue)
                Text("최근 변경")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PTKTheme.faint)
                Spacer(minLength: 0)
            }

            ForEach(visibleChanges) { change in
                let displayData = recentChangeDisplayData(change, relativeTo: now)
                HStack(spacing: 7) {
                    Image(systemName: displayData.systemImageName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PTKTheme.blue)
                        .frame(width: 13)
                    Text(displayData.primaryText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PTKTheme.text)
                        .lineLimit(1)
                    if let detailText = displayData.detailText {
                        Text(detailText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(PTKTheme.faint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Text(displayData.timeText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PTKTheme.faint)
                        .lineLimit(1)
                }
                .accessibilityLabel(displayData.accessibilityText)
                .help(displayData.helpText)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PTKTheme.blue.opacity(0.10)))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(PTKTheme.blue.opacity(0.18), lineWidth: 1)
        }
        .help(recentChangesHelp(relativeTo: now))
    }

    private var visibleChanges: ArraySlice<PortChange> {
        viewModel.recentPortChanges.prefix(4)
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
