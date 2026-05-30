import Darwin

public struct KillTarget: Equatable, Sendable {
    public let port: UInt16
    public let pid: Int
    public let processName: String

    public init?(port: UInt16, pid: Int?, processName: String?) {
        guard let pid, pid > 0, let processName, !processName.isEmpty else {
            return nil
        }
        self.port = port
        self.pid = pid
        self.processName = processName
    }

    public init(port: UInt16, pid: Int, processName: String) {
        self.port = port
        self.pid = pid
        self.processName = processName
    }
}

public enum KillError: Error, Equatable, CustomStringConvertible {
    case unsafeTarget
    case lookupFailed
    case pidChanged(expected: Int, actual: Int)
    case processNameMismatch(expected: String, actual: String)
    case terminationFailed(String)

    public var description: String {
        switch self {
        case .unsafeTarget:
            return "kill target is missing a safe PID or process name"
        case .lookupFailed:
            return "process lookup failed; refresh and try again"
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
    public init() {}

    public func terminate(pid: Int) -> String? {
        guard pid > 0 else { return "invalid PID" }
        if Darwin.kill(pid_t(pid), SIGTERM) == 0 {
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
        guard let current = try resolver.info(for: target.port), let currentName = current.processName else {
            throw KillError.lookupFailed
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
