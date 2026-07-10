import Darwin

public struct KillTarget: Equatable, Sendable {
    public let port: UInt16
    public let pid: Int
    public let processName: String

    public init(port: UInt16, pid: Int, processName: String) {
        self.port = port
        self.pid = pid
        self.processName = processName
    }

    public static func safe(port: UInt16, pid: Int?, processName: String?) -> KillTarget? {
        guard let pid, pid > 0, let processName, !processName.isEmpty else {
            return nil
        }
        return KillTarget(port: port, pid: pid, processName: processName)
    }
}

public enum KillError: Error, Equatable, CustomStringConvertible {
    case unsafeTarget
    case portNoLongerListening
    case processNameUnavailable
    case resolverFailed(String)
    case pidChanged(expected: Int, actual: Int)
    case processNameMismatch(expected: String, actual: String)
    case terminationFailed(String)

    public var description: String {
        switch self {
        case .unsafeTarget:
            return "kill target is missing a safe PID or process name"
        case .portNoLongerListening:
            return "port is no longer listening; refresh and try again"
        case .processNameUnavailable:
            return "process name is unavailable; refresh and try again"
        case .resolverFailed(let message):
            return "process lookup failed: \(message)"
        case .pidChanged(let expected, let actual):
            return "PID changed from \(expected) to \(actual); refresh and try again"
        case .processNameMismatch(let expected, let actual):
            return "process changed from \(expected) to \(actual); refresh and try again"
        case .terminationFailed(let message):
            return "termination failed: \(message)"
        }
    }
}

public enum KillOutcome: Equatable, Sendable {
    case cancelled
    case terminated
}

public protocol ProcessResolving {
    func info(for port: UInt16) throws -> PortProcessInfo?
}

extension ProcessLookup: ProcessResolving {}

public protocol ProcessTerminating {
    func terminate(pid: Int) -> String?
}

public struct SystemProcessTerminator: ProcessTerminating {
    private let signalSender: (pid_t, Int32) -> Int32

    public init() {
        signalSender = { Darwin.kill($0, $1) }
    }

    init(signalSender: @escaping (pid_t, Int32) -> Int32) {
        self.signalSender = signalSender
    }

    public func terminate(pid: Int) -> String? {
        guard pid > 0 else { return "invalid PID" }
        if signalSender(pid_t(pid), SIGTERM) == 0 {
            return nil
        }
        return String(cString: strerror(errno))
    }
}

public protocol KillConfirming {
    func confirmKill(target: KillTarget) -> Bool
}

public struct KillService {
    private let resolver: ProcessResolving
    private let terminator: ProcessTerminating

    public init(
        resolver: ProcessResolving = ProcessLookup(),
        terminator: ProcessTerminating = SystemProcessTerminator()
    ) {
        self.resolver = resolver
        self.terminator = terminator
    }

    public func terminateAfterRevalidation(target: KillTarget) throws {
        let current: PortProcessInfo?
        do {
            current = try resolver.info(for: target.port)
        } catch {
            throw KillError.resolverFailed("\(error)")
        }

        guard let current else {
            throw KillError.portNoLongerListening
        }
        guard let currentName = current.processName, !currentName.isEmpty else {
            throw KillError.processNameUnavailable
        }
        guard current.pid == target.pid else {
            throw KillError.pidChanged(expected: target.pid, actual: current.pid)
        }
        guard currentName == target.processName else {
            throw KillError.processNameMismatch(expected: target.processName, actual: currentName)
        }

        if let message = terminator.terminate(pid: target.pid) {
            throw KillError.terminationFailed(message)
        }
    }
}

public struct KillCoordinator {
    private let confirmer: KillConfirming
    private let service: KillService

    public init(confirmer: KillConfirming, service: KillService) {
        self.confirmer = confirmer
        self.service = service
    }

    public func requestKill(target: KillTarget?) throws -> KillOutcome {
        guard let target else { throw KillError.unsafeTarget }
        guard confirmer.confirmKill(target: target) else { return .cancelled }
        try service.terminateAfterRevalidation(target: target)
        return .terminated
    }
}
