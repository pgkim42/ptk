import SwiftUI

struct PanelFooterView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: PTKSpace.sm) {
            profileQuickSwitch

            if let message = viewModel.copyFeedbackMessage {
                Text(message)
                    .font(PTKType.ui(11, weight: .medium))
                    .foregroundStyle(PTKTheme.muted)
                    .accessibilityLabel(message)
            } else {
                Text(viewModel.refreshInterval.label)
                    .font(PTKType.mono(11))
                    .foregroundStyle(PTKTheme.faint)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            PanelIconButton(
                systemName: "doc.on.doc",
                help: "열린 포트 요약 복사",
                accessibilityHint: "현재 열린 모든 포트의 정보를 클립보드에 복사합니다."
            ) {
                viewModel.copyOpenPortsSummary()
            }

            PanelIconButton(
                systemName: "gearshape",
                help: "설정 열기",
                accessibilityHint: "감시 포트, 새로고침 주기와 테마 설정을 엽니다."
            ) {
                viewModel.isShowingSettings = true
            }

            PanelIconButton(
                systemName: "power",
                help: "PTK 종료",
                accessibilityHint: "PTK 메뉴 막대 앱을 종료합니다."
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, PTKSpace.md)
        .frame(height: 34)
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
                .accessibilityLabel("프로필 \(option.title) 적용")
                .accessibilityHint("감시 포트를 \(option.expression)(으)로 변경합니다.")
            }
        } label: {
            Text(viewModel.currentProfileTitle)
                .font(PTKType.ui(11, weight: .medium))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 128, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("감시 포트 프로필 빠른 전환")
        .accessibilityLabel("감시 포트 프로필 선택, 현재 \(viewModel.currentProfileTitle)")
        .accessibilityHint("적용할 감시 포트 프로필 메뉴를 엽니다.")
    }
}
