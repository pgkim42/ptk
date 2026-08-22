import SwiftUI

struct PortSummaryHeaderView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: PTKSpace.sm) {
            Text("PTK")
                .font(PTKType.ui(13, weight: .semibold))
                .foregroundStyle(PTKTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("\(viewModel.openPorts.count)")
                .font(PTKType.mono(12, weight: .semibold))
                .foregroundStyle(viewModel.openPorts.isEmpty ? PTKTheme.faint : PTKTheme.ink)
                .monospacedDigit()
                .lineLimit(1)
            Text("열림")
                .font(PTKType.ui(11))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)

            PanelIconButton(
                systemName: "arrow.clockwise",
                help: "새로고침",
                accessibilityHint: "포트와 서비스 상태를 지금 다시 확인합니다."
            ) {
                viewModel.refresh()
            }
        }
        .padding(.horizontal, PTKSpace.md)
        .frame(height: 36)
        .layoutPriority(2)
        .accessibilityElement(children: .contain)
    }
}
