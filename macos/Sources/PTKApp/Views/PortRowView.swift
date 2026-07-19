import SwiftUI
import PTKCore

struct PortRowView: View {
    let status: PortStatus
    let onOpen: (PortStatus) -> Void
    let onCopy: (PortStatus) -> Void
    let onCopyDetails: (PortStatus) -> Void
    let onKill: (KillTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Circle()
                    .fill(PTKTheme.green)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(verbatim: "\(status.port)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(PTKTheme.text)
                    .lineLimit(1)
                    .frame(width: 46, alignment: .leading)

                if let pid = status.pid {
                    Text(verbatim: "PID \(pid)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PTKTheme.muted)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)
                } else {
                    Text("PID -")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PTKTheme.faint)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)
                }

                if let processDisplayName {
                    Text(verbatim: processDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PTKTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(processHelpText)
                } else {
                    Text("알 수 없음")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PTKTheme.faint)
                }

                Spacer()

                Button {
                    onOpen(status)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 22))
                .help("로컬 주소 열기")
                .accessibilityLabel(PortRowAccessibility.openLabel(for: status))
                .accessibilityHint(PortRowAccessibility.openHint(for: status))

                Button {
                    onCopy(status)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 22))
                .help("로컬 주소 복사")
                .accessibilityLabel(PortRowAccessibility.copyURLLabel(for: status))
                .accessibilityHint(PortRowAccessibility.copyURLHint(for: status))

                Button {
                    onCopyDetails(status)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 22))
                .help("포트 정보 복사")
                .accessibilityLabel(PortRowAccessibility.copyDetailsLabel(for: status))
                .accessibilityHint(PortRowAccessibility.copyDetailsHint(for: status))

                if let target = status.killTarget {
                    Button {
                        onKill(target)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.red, size: 22))
                    .help("프로세스 종료")
                    .accessibilityLabel(PortRowAccessibility.killLabel(for: target))
                    .accessibilityHint(PortRowAccessibility.killHint)
                } else if let reason = status.ptkKillUnavailableReason {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PTKTheme.orange)
                        .frame(width: 22, height: 22)
                        .help(reason)
                        .accessibilityLabel(PortRowAccessibility.diagnosticLabel(for: status, reason: reason))
                }
            }

            if let diagnostic = status.ptkKillUnavailableDiagnostic {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(diagnostic.title)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(PTKTheme.orange)
                .padding(.leading, 61)
                .help(diagnosticHelpText(diagnostic))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PortRowAccessibility.diagnosticLabel(for: status, reason: diagnosticHelpText(diagnostic)))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, status.ptkKillUnavailableReason == nil ? 0 : 4)
        .frame(minHeight: PortRowMetrics.height(for: status))
        .background(Color.clear)
    }

    private var processDisplayName: String? {
        guard let processName = status.processName, !processName.isEmpty else {
            return nil
        }
        return processName.ptkDisplayProcessName
    }

    private var processHelpText: String {
        status.processName ?? ""
    }

    private func diagnosticHelpText(_ diagnostic: KillUnavailableDiagnostic) -> String {
        [diagnostic.title, diagnostic.detail, diagnostic.hint]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

enum PortRowAccessibility {
    static func openLabel(for status: PortStatus) -> String {
        "포트 \(status.port) 로컬 주소 열기"
    }

    static func openHint(for status: PortStatus) -> String {
        "기본 웹 브라우저에서 http://localhost:\(status.port)을 엽니다."
    }

    static func copyURLLabel(for status: PortStatus) -> String {
        "포트 \(status.port) 로컬 주소 복사"
    }

    static func copyURLHint(for status: PortStatus) -> String {
        "http://localhost:\(status.port)을 클립보드에 복사합니다."
    }

    static func copyDetailsLabel(for status: PortStatus) -> String {
        "포트 \(status.port) 정보 복사"
    }

    static func copyDetailsHint(for status: PortStatus) -> String {
        let process: String
        if let processName = status.processName, !processName.isEmpty {
            process = processName
        } else {
            process = "알 수 없는 프로세스"
        }
        return "\(process)의 포트 정보를 클립보드에 복사합니다."
    }

    static func killLabel(for target: KillTarget) -> String {
        "포트 \(target.port), \(target.processName), PID \(target.pid) 프로세스 종료"
    }

    static let killHint = "확인 후 프로세스에 SIGTERM 신호를 보냅니다."

    static func diagnosticLabel(for status: PortStatus, reason: String) -> String {
        "포트 \(status.port) 프로세스 종료 불가: \(reason)"
    }
}
