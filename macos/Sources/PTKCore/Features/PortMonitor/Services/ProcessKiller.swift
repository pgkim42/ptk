import Darwin

public struct KillTarget: Equatable, Sendable {
    public let port: UInt16
    public let identity: VerifiedProcessIdentity

    public var pid: Int { identity.pid }
    public var processName: String { identity.processName }

    init(port: UInt16, identity: VerifiedProcessIdentity) {
        self.port = port
        self.identity = identity
    }

    init(port: UInt16, pid: Int, processName: String) {
        self.init(
            port: port,
            identity: VerifiedProcessIdentity(pid: pid, processName: processName)!
        )
    }
}

public enum KillError: Error, Equatable, CustomStringConvertible {
    case unsafeTarget
    case portNoLongerListening
    case processNameUnavailable
    case resolverFailed(String)
    case untrustedListener(port: UInt16, reasons: [LsofUntrustedReason])
    case ambiguousListeners(port: UInt16, pids: [Int])
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
        case .untrustedListener(let port, let reasons):
            let reasonList = normalizedKillUntrustedReasons(reasons)
                .map { String(describing: $0) }
                .joined(separator: ", ")
            return "untrusted listener for port \(port): \(reasonList); refresh and try again"
        case .ambiguousListeners(let port, let pids):
            let pidList = pids.sorted().map(String.init).joined(separator: ", ")
            return "ambiguous listeners for port \(port): PIDs \(pidList); refresh and try again"
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

public protocol ProcessResolving: Sendable {
    func info(for port: UInt16) throws -> PortProcessInfo?
}

extension ProcessLookup: ProcessResolving {}

public protocol ProcessTerminating: Sendable {
    func terminate(pid: Int) -> String?
}

public struct SystemProcessTerminator: ProcessTerminating {
    private let signalSender: @Sendable (pid_t, Int32) -> Int32

    public init() {
        signalSender = { Darwin.kill($0, $1) }
    }

    init(signalSender: @escaping @Sendable (pid_t, Int32) -> Int32) {
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

public struct KillService: Sendable {
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
        } catch ProcessLookupError.untrustedListeners(let port, let reasons) {
            throw KillError.untrustedListener(
                port: port,
                reasons: normalizedKillUntrustedReasons(reasons)
            )
        } catch ProcessLookupError.ambiguousListeners(let port, let pids) {
            throw KillError.ambiguousListeners(port: port, pids: pids.sorted())
        } catch {
            throw KillError.resolverFailed("\(error)")
        }

        guard let current else {
            throw KillError.portNoLongerListening
        }
        guard current.pid == target.pid else {
            throw KillError.pidChanged(expected: target.pid, actual: current.pid)
        }
        guard current.processName == target.processName else {
            throw KillError.processNameMismatch(
                expected: target.processName,
                actual: current.processName
            )
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

private func normalizedKillUntrustedReasons(
    _ reasons: [LsofUntrustedReason]
) -> [LsofUntrustedReason] {
    Array(Set(reasons)).sorted {
        killUntrustedReasonOrder($0) < killUntrustedReasonOrder($1)
    }
}

private func killUntrustedReasonOrder(_ reason: LsofUntrustedReason) -> Int {
    switch reason {
    case .remoteOrInterfaceOnly:
        0
    case .established:
        1
    case .unknownFamily:
        2
    case .unknownAddress:
        3
    case .malformed:
        4
    case .familyAddressConflict:
        5
    }
}
