import SwiftUI

struct PortSummaryHeaderView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("PTK")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)

            Text("Port Toolkit")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)

            Spacer()

            Text(verbatim: "\(viewModel.openPorts.count) OPEN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(viewModel.openPorts.isEmpty ? PTKTheme.faint : PTKTheme.green)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(viewModel.openPorts.isEmpty ? PTKTheme.card : PTKTheme.green.opacity(0.14)))
                .overlay {
                    Capsule().strokeBorder(viewModel.openPorts.isEmpty ? PTKTheme.border : PTKTheme.green.opacity(0.22), lineWidth: 1)
                }

            PanelIconButton(
                systemName: "arrow.clockwise",
                help: "새로고침",
                accessibilityHint: "포트와 서비스 상태를 지금 다시 확인합니다."
            ) {
                viewModel.refresh()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .layoutPriority(2)
    }
}
