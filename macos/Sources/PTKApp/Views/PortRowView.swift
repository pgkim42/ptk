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
                    Text("unknown")
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
                .help("localhost 열기")

                Button {
                    onCopy(status)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 22))
                .help("localhost URL 복사")

                Button {
                    onCopyDetails(status)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 22))
                .help("포트 정보 복사")

                if let target = status.killTarget {
                    Button {
                        onKill(target)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.red, size: 22))
                    .help("프로세스 종료")
                } else if let reason = status.ptkKillUnavailableReason {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PTKTheme.orange)
                        .frame(width: 22, height: 22)
                        .help(reason)
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
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, status.ptkKillUnavailableReason == nil ? 0 : 4)
        .frame(minHeight: status.ptkKillUnavailableReason == nil ? 29 : 44)
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
