import SwiftUI

struct PanelFooterView: View {
    @ObservedObject var viewModel: PortMonitorViewModel

    var body: some View {
        HStack(spacing: 8) {
            profileQuickSwitch

            Group {
                if let message = viewModel.copyFeedbackMessage {
                    Label(message, systemImage: "checkmark")
                        .accessibilityLabel(message)
                } else {
                    Text(viewModel.refreshInterval.label)
                }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(PTKTheme.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(PTKTheme.card))

            Spacer()

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
                    .accessibilityLabel("프로필 \(option.title) 적용")
                    .accessibilityHint("감시 포트를 \(option.expression)(으)로 변경합니다.")
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
        .accessibilityLabel("감시 포트 프로필 선택, 현재 \(viewModel.currentProfileTitle)")
        .accessibilityHint("적용할 감시 포트 프로필 메뉴를 엽니다.")
    }
}
