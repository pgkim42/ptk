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

            Text(status.state.label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(indicatorColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(indicatorColor.opacity(0.10)))
                .overlay {
                    Capsule().strokeBorder(indicatorColor.opacity(0.15), lineWidth: 1)
                }
        }
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(Color.clear)
    }

    private var indicatorColor: Color {
        switch status.state {
        case .running: PTKTheme.green
        case .stopped: PTKTheme.red
        case .unavailable: PTKTheme.orange
        }
    }
}
