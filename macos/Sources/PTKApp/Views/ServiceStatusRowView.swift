import SwiftUI
import PTKCore

struct ServiceStatusRowView: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 8) {
            PTKStatusDot(color: indicatorColor)

            Text(status.name)
                .font(PTKType.ui(12, weight: .medium))
                .foregroundStyle(PTKTheme.ink)
                .lineLimit(1)
                .frame(width: 86, alignment: .leading)

            Text(status.detail)
                .font(PTKType.ui(11))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(status.state.label)
                .font(PTKType.ui(11))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, PTKSpace.sm)
        .frame(height: ServiceStatusListMetrics.statusRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ServiceRowAccessibility.statusLabel(for: status))
    }

    private var indicatorColor: Color {
        switch status.state {
        case .running: PTKTheme.running
        case .stopped: PTKTheme.danger.opacity(0.75)
        case .unavailable: PTKTheme.caution
        }
    }
}

struct DockerContainerPortRowView: View {
    let row: DockerContainerPortRow
    let onCopyURL: () -> Void

    init(row: DockerContainerPortRow, onCopyURL: @escaping () -> Void = {}) {
        self.row = row
        self.onCopyURL = onCopyURL
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(row.name)
                .font(PTKType.ui(11, weight: .medium))
                .foregroundStyle(row.isSummary ? PTKTheme.faint : PTKTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64, alignment: .leading)

            Text(row.detail)
                .font(PTKType.mono(10))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if !row.isSummary, let candidate = row.copyCandidates.first, row.copyCandidates.count == 1 {
                Button {
                    onCopyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 18))
                .help("Docker 주소 복사: \(candidate.urlString)")
                .accessibilityLabel(ServiceRowAccessibility.copyLabel(for: row, url: candidate.urlString))
                .accessibilityHint(ServiceRowAccessibility.copyHint(for: candidate.urlString))
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, PTKSpace.sm)
        .frame(height: 22)
        .help(row.isSummary ? row.detail : "\(row.name) \(row.detail)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ServiceRowAccessibility.containerLabel(for: row))
    }
}

struct ServiceStatusEmptyRowView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(PTKType.ui(11))
            .foregroundStyle(PTKTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PTKSpace.sm)
            .padding(.vertical, PTKSpace.sm)
            .help(message)
    }
}

enum ServiceRowAccessibility {
    static func statusLabel(for status: ServiceStatus) -> String {
        "\(status.name) 서비스, \(status.detail), 상태 \(status.state.label)"
    }

    static func copyLabel(for row: DockerContainerPortRow, url: String) -> String {
        "Docker 서비스 \(row.name) 주소 복사, \(url)"
    }

    static func copyHint(for url: String) -> String {
        "\(url)을 클립보드에 복사합니다."
    }

    static func containerLabel(for row: DockerContainerPortRow) -> String {
        row.isSummary ? row.detail : "Docker 서비스 \(row.name), \(row.detail)"
    }
}
