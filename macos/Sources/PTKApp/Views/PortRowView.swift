import SwiftUI
import PTKCore

struct PortRowView: View {
    let status: PortStatus
    let onKill: (KillTarget) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PTKTheme.green)
                .frame(width: 7, height: 7)

            Text("\(status.port)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(PTKTheme.text)
                .lineLimit(1)
                .frame(width: 46, alignment: .leading)

            if let pid = status.pid {
                Text("PID \(pid)")
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

            if let processName = status.processName, !processName.isEmpty {
                Text(processName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PTKTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("unknown")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PTKTheme.faint)
            }

            Spacer()

            if let target = KillTarget.safe(port: status.port, pid: status.pid, processName: status.processName) {
                Button {
                    onKill(target)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("프로세스 종료")
                .foregroundStyle(PTKTheme.red)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(Color.clear)
    }
}
