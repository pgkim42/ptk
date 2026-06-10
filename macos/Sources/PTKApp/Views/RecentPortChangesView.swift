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
