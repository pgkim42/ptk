import SwiftUI
import PTKCore

struct ServiceStatusRowView: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)

            Text(status.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PTKTheme.text)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)

            Text(status.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)

            Spacer()

            Text(status.state.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(badgeForegroundColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(badgeBackgroundColor))
                .overlay {
                    Capsule().strokeBorder(badgeBorderColor, lineWidth: 1)
                }
        }
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ServiceRowAccessibility.statusLabel(for: status))
    }

    private var indicatorColor: Color {
        switch status.state {
        case .running: PTKTheme.green
        case .stopped: PTKTheme.red.opacity(0.72)
        case .unavailable: PTKTheme.orange
        }
    }

    private var badgeForegroundColor: Color {
        switch status.state {
        case .running: PTKTheme.green
        case .stopped: PTKTheme.faint
        case .unavailable: PTKTheme.orange
        }
    }

    private var badgeBackgroundColor: Color {
        switch status.state {
        case .running, .unavailable: indicatorColor.opacity(0.10)
        case .stopped: PTKTheme.card
        }
    }

    private var badgeBorderColor: Color {
        switch status.state {
        case .running, .unavailable: indicatorColor.opacity(0.15)
        case .stopped: PTKTheme.border
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
        HStack(spacing: 7) {
            Spacer()
                .frame(width: 12)

            Image(systemName: row.isSummary ? "ellipsis" : "arrow.turn.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(PTKTheme.faint)
                .frame(width: 12)

            Text(row.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(row.isSummary ? PTKTheme.faint : PTKTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 92, alignment: .leading)

            Text(row.detail)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)
                .truncationMode(.tail)


            if !row.isSummary, let candidate = row.copyCandidates.first, row.copyCandidates.count == 1 {
                Button(action: onCopyURL) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 20))
                .help("Docker 주소 복사: \(candidate.urlString)")
                .accessibilityLabel(ServiceRowAccessibility.copyLabel(for: row, url: candidate.urlString))
                .accessibilityHint(ServiceRowAccessibility.copyHint(for: candidate.urlString))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(PTKTheme.card.opacity(0.28))
        .help(row.isSummary ? row.detail : "\(row.name) \(row.detail)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ServiceRowAccessibility.containerLabel(for: row))
    }
}

struct ServiceStatusEmptyRowView: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PTKTheme.faint)
                .frame(width: 12)

            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(PTKTheme.card.opacity(0.18))
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
