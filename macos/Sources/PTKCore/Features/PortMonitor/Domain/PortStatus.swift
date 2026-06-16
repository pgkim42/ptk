import Foundation

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

public enum KillUnavailableCause: Equatable, Sendable {
    case ambiguousListener(message: String)
    case lookupFailed(message: String)
    case missingPID
    case missingProcessName(pid: Int)
}

public extension PortStatus {
    var killUnavailableCause: KillUnavailableCause? {
        guard isOpen else { return nil }
        guard KillTarget.safe(port: port, pid: pid, processName: processName) == nil else {
            return nil
        }
        if let message, !message.isEmpty {
            if message.localizedCaseInsensitiveContains("ambiguous") {
                return .ambiguousListener(message: message)
            }
            return .lookupFailed(message: message)
        }
        guard let pid, pid > 0 else {
            return .missingPID
        }
        guard let processName, !processName.isEmpty else {
            return .missingProcessName(pid: pid)
        }
        return nil
    }
}

public enum PortChangeKind: String, Equatable, Sendable {
    case opened
    case closed
    case changed
}

public struct PortChange: Equatable, Identifiable, Sendable {
    public let id: String
    public let port: UInt16
    public let kind: PortChangeKind
    public let pid: Int?
    public let processName: String?
    public let occurredAt: Date

    public init(
        port: UInt16,
        kind: PortChangeKind,
        pid: Int? = nil,
        processName: String? = nil,
        occurredAt: Date = Date()
    ) {
        let pidIdentity = pid.map { "pid:\($0)" } ?? "pid:nil"
        let processIdentity = processName.map { "process:\($0)" } ?? "process:nil"
        self.id = "\(port)-\(kind.rawValue)-\(pidIdentity)-\(processIdentity)-occurred:\(occurredAt.timeIntervalSince1970)"
        self.port = port
        self.kind = kind
        self.pid = pid
        self.processName = processName
        self.occurredAt = occurredAt
    }

    public static func detect(
        previous: [PortStatus],
        current: [PortStatus],
        occurredAt: Date = Date()
    ) -> [PortChange] {
        let previousByPort = Dictionary(uniqueKeysWithValues: previous.map { ($0.port, $0) })
        return current.compactMap { status in
            guard let previousStatus = previousByPort[status.port] else { return nil }
            if previousStatus.isOpen != status.isOpen {
                return PortChange(
                    port: status.port,
                    kind: status.isOpen ? .opened : .closed,
                    pid: status.pid,
                    processName: status.processName,
                    occurredAt: occurredAt
                )
            }
            if status.isOpen,
               previousStatus.pid != status.pid || previousStatus.processName != status.processName {
                return PortChange(
                    port: status.port,
                    kind: .changed,
                    pid: status.pid,
                    processName: status.processName,
                    occurredAt: occurredAt
                )
            }
            return nil
        }
    }
}
