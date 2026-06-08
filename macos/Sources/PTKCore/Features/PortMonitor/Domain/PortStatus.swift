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

public extension PortStatus {
    var killUnavailableReason: String? {
        guard isOpen else { return nil }
        guard KillTarget.safe(port: port, pid: pid, processName: processName) == nil else {
            return nil
        }
        if let message, !message.isEmpty {
            return message
        }
        guard let pid, pid > 0 else {
            return "process lookup unavailable: PID not found"
        }
        guard let processName, !processName.isEmpty else {
            return "process lookup unavailable: process name not found"
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
