import Foundation

public struct VerifiedProcessIdentity: Equatable, Sendable {
    public let pid: Int
    public let processName: String

    init?(pid: Int, processName: String) {
        let trimmedProcessName = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pid > 0, !trimmedProcessName.isEmpty else { return nil }

        self.pid = pid
        self.processName = trimmedProcessName
    }
}

public enum PortIdentityUnavailableCause: Equatable, Sendable {
    case noVerifiedListener
    case untrustedListener(message: String)
    case ambiguousListeners(pids: [Int])
    case lookupFailed(message: String)
    case processNameUnavailable(pid: Int)
}

public enum PortIdentityState: Equatable, Sendable {
    case verified(VerifiedProcessIdentity)
    case unavailable(PortIdentityUnavailableCause)
}

public struct PortStatus: Equatable, Sendable {
    public let port: UInt16
    public let isOpen: Bool
    public let identityState: PortIdentityState?

    public var verifiedIdentity: VerifiedProcessIdentity? {
        guard case .verified(let identity) = identityState else { return nil }
        return identity
    }

    public var pid: Int? {
        verifiedIdentity?.pid
    }

    public var processName: String? {
        verifiedIdentity?.processName
    }

    public var message: String? {
        switch identityState {
        case .unavailable(.untrustedListener(let message)),
             .unavailable(.lookupFailed(let message)):
            message
        case .unavailable(.ambiguousListeners(let pids)):
            "ambiguous process lookup: port \(port) has PIDs \(pids.map(String.init).joined(separator: ", "))"
        case .verified, .unavailable(.noVerifiedListener),
             .unavailable(.processNameUnavailable), nil:
            nil
        }
    }

    public var killTarget: KillTarget? {
        guard let identity = verifiedIdentity else { return nil }
        return KillTarget(port: port, pid: identity.pid, processName: identity.processName)
    }

    public init(
        port: UInt16,
        isOpen: Bool,
        identityState: PortIdentityState?
    ) {
        self.port = port
        self.isOpen = isOpen
        self.identityState = isOpen
            ? identityState ?? .unavailable(.noVerifiedListener)
            : nil
    }

    init(
        port: UInt16,
        isOpen: Bool,
        pid: Int? = nil,
        processName: String? = nil,
        message: String? = nil
    ) {
        let identityState: PortIdentityState?
        if !isOpen {
            identityState = nil
        } else if let pid,
                  let processName,
                  let identity = VerifiedProcessIdentity(pid: pid, processName: processName) {
            identityState = .verified(identity)
        } else {
            identityState = .unavailable(Self.unavailableCause(
                pid: pid,
                message: message
            ))
        }

        self.init(port: port, isOpen: isOpen, identityState: identityState)
    }

    private static func unavailableCause(
        pid: Int?,
        message: String?
    ) -> PortIdentityUnavailableCause {
        if let message, !message.isEmpty {
            let pids = ambiguousPIDs(in: message)
            if !pids.isEmpty {
                return .ambiguousListeners(pids: pids)
            }
            return .lookupFailed(message: message)
        }
        if let pid, pid > 0 {
            return .processNameUnavailable(pid: pid)
        }
        return .noVerifiedListener
    }

    private static func ambiguousPIDs(in message: String) -> [Int] {
        guard message.localizedCaseInsensitiveContains("ambiguous"),
              let markerRange = message.range(of: "PIDs", options: .caseInsensitive) else {
            return []
        }

        return message[markerRange.upperBound...]
            .split(separator: ",")
            .compactMap { component in
                Int(component.trimmingCharacters(in: .whitespacesAndNewlines))
            }
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
        guard case .unavailable(let cause) = identityState else { return nil }

        switch cause {
        case .noVerifiedListener:
            return .missingPID
        case .untrustedListener(let message), .lookupFailed(let message):
            return .lookupFailed(message: message)
        case .ambiguousListeners:
            return .ambiguousListener(message: message ?? "")
        case .processNameUnavailable(let pid):
            return .missingProcessName(pid: pid)
        }
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
               let previousIdentity = previousStatus.verifiedIdentity,
               let currentIdentity = status.verifiedIdentity,
               previousIdentity != currentIdentity {
                return PortChange(
                    port: status.port,
                    kind: .changed,
                    pid: currentIdentity.pid,
                    processName: currentIdentity.processName,
                    occurredAt: occurredAt
                )
            }
            return nil
        }
    }

    public static func mergedBaseline(
        previous: [PortStatus]?,
        current: [PortStatus]
    ) -> [PortStatus] {
        guard let previous else { return current }

        let previousByPort = Dictionary(uniqueKeysWithValues: previous.map { ($0.port, $0) })
        return current.map { status in
            guard status.isOpen,
                  status.verifiedIdentity == nil,
                  let previousStatus = previousByPort[status.port],
                  previousStatus.isOpen,
                  previousStatus.verifiedIdentity != nil else {
                return status
            }
            return previousStatus
        }
    }
}
