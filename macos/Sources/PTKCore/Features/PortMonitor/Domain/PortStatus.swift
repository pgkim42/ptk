public struct PortStatus: Equatable, Sendable {
    public let port: UInt16
    public let isOpen: Bool
    public let pid: Int?
    public let processName: String?
    public let message: String?

    public init(
        port: UInt16,
        isOpen: Bool,
        pid: Int? = nil,
        processName: String? = nil,
        message: String? = nil
    ) {
        self.port = port
        self.isOpen = isOpen
        self.pid = pid
        self.processName = processName
        self.message = message
    }
}

public struct KillUnavailableDiagnostic: Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let hint: String

    public init(title: String, detail: String? = nil, hint: String) {
        self.title = title
        self.detail = detail
        self.hint = hint
    }
}


public extension PortStatus {
    var killUnavailableReason: String? {
        killUnavailableDiagnostic?.title
    }

    var killUnavailableDiagnostic: KillUnavailableDiagnostic? {
        guard isOpen else { return nil }
        guard KillTarget.safe(port: port, pid: pid, processName: processName) == nil else {
            return nil
        }
        if let message, !message.isEmpty {
            if message.localizedCaseInsensitiveContains("ambiguous") {
                return KillUnavailableDiagnostic(
                    title: "여러 listener가 있어 안전하게 종료할 수 없음",
                    detail: message,
                    hint: "포트 \(port)를 점유한 프로세스를 터미널에서 직접 확인한 뒤 정리하세요."
                )
            }
            return KillUnavailableDiagnostic(
                title: "프로세스 조회 실패로 안전하게 종료할 수 없음",
                detail: message,
                hint: "새로고침 후에도 반복되면 lsof/ps 결과를 확인하세요."
            )
        }
        guard let pid, pid > 0 else {
            return KillUnavailableDiagnostic(
                title: "PID를 찾을 수 없어 안전하게 종료할 수 없음",
                hint: "프로세스 조회 권한 또는 포트 상태를 확인한 뒤 다시 새로고침하세요."
            )
        }
        guard let processName, !processName.isEmpty else {
            return KillUnavailableDiagnostic(
                title: "프로세스 이름을 확인할 수 없어 안전하게 종료할 수 없음",
                hint: "PID \(pid)의 프로세스가 바뀌었을 수 있으니 다시 새로고침하세요."
            )
        }
        return nil
    }
}

public enum PortChangeKind: String, Equatable, Sendable {
    case opened
    case closed
    case changed

    public var label: String {
        switch self {
        case .opened:
            return "열림"
        case .closed:
            return "닫힘"
        case .changed:
            return "변경"
        }
    }
}

public struct PortChange: Equatable, Identifiable, Sendable {
    public let id: String
    public let port: UInt16
    public let kind: PortChangeKind
    public let pid: Int?
    public let processName: String?

    public init(port: UInt16, kind: PortChangeKind, pid: Int? = nil, processName: String? = nil) {
        self.id = "\(port)-\(kind.rawValue)-\(pid ?? 0)-\(processName ?? "")"
        self.port = port
        self.kind = kind
        self.pid = pid
        self.processName = processName
    }

    public var displayText: String {
        var parts = ["\(port)", kind.label]
        if let processName, !processName.isEmpty {
            parts.append(processName)
        }
        if let pid {
            parts.append("PID \(pid)")
        }
        return parts.joined(separator: " · ")
    }

    public static func detect(previous: [PortStatus], current: [PortStatus]) -> [PortChange] {
        let previousByPort = Dictionary(uniqueKeysWithValues: previous.map { ($0.port, $0) })
        return current.compactMap { status in
            guard let previousStatus = previousByPort[status.port] else { return nil }
            if previousStatus.isOpen != status.isOpen {
                return PortChange(
                    port: status.port,
                    kind: status.isOpen ? .opened : .closed,
                    pid: status.pid,
                    processName: status.processName
                )
            }
            if status.isOpen,
               previousStatus.pid != status.pid || previousStatus.processName != status.processName {
                return PortChange(
                    port: status.port,
                    kind: .changed,
                    pid: status.pid,
                    processName: status.processName
                )
            }
            return nil
        }
    }
}
