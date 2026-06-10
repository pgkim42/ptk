import SwiftUI

struct PanelFooterView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: 8) {
            profileQuickSwitch

            Text(viewModel.refreshInterval.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PTKTheme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(PTKTheme.card))

            Spacer()

            PanelIconButton(systemName: "doc.on.doc", help: "열린 포트 요약 복사") {
                viewModel.copyOpenPortsSummary()
            }

            PanelIconButton(systemName: "gearshape", help: "설정") {
                viewModel.isShowingSettings = true
            }

            PanelIconButton(systemName: "power", help: "종료") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .layoutPriority(2)
    }

    private var profileQuickSwitch: some View {
        Menu {
            ForEach(viewModel.profileOptions) { option in
                Button {
                    do {
                        try viewModel.applyProfileOption(option)
                    } catch {
                        viewModel.errorMessage = "프로필 적용 오류: \(error)"
                    }
                } label: {
                    Text(option.title)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                Text(viewModel.currentProfileTitle)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(PTKTheme.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: 110)
            .background(Capsule().fill(PTKTheme.card))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("감시 포트 프로필 빠른 전환")
    }
}
