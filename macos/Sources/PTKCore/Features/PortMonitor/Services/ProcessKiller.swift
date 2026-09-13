import Darwin
import Foundation

public struct KillTarget: Equatable, Sendable {
    public let port: UInt16
    public let identity: VerifiedProcessIdentity

    public var pid: Int { identity.pid }
    public var processName: String { identity.processName }

    init(port: UInt16, identity: VerifiedProcessIdentity) {
        self.port = port
        self.identity = identity
    }

    init(port: UInt16, pid: Int, processName: String, startTime: ProcessStartTime) {
        self.init(
            port: port,
            identity: VerifiedProcessIdentity(pid: pid, processName: processName, startTime: startTime)!
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
    case processRestarted(pid: Int)
    case terminationFailed(String)
    case portStillListening(port: UInt16)
    case portReoccupied(port: UInt16, pid: Int)
    case terminationUnconfirmed(String)

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
            let reasonList = reasons.normalizedByResolutionOrder
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
        case .processRestarted(let pid):
            return "process start time changed for PID \(pid); refresh and try again"
        case .terminationFailed(let message):
            return "termination failed: \(message)"
        case .portStillListening(let port):
            return "종료 신호를 보냈지만 포트 \(port)가 아직 열려 있습니다. 강제 종료하지 않았습니다."
        case .portReoccupied(let port, let pid):
            return "포트 \(port)를 다른 실행(PID \(pid))이 점유하고 있습니다. 새 실행에는 종료 신호를 보내지 않았습니다."
        case .terminationUnconfirmed(let message):
            return "종료 신호를 보냈지만 포트 해제를 확인하지 못했습니다: \(message)"
        }
    }
}

public enum KillOutcome: Equatable, Sendable {
    case cancelled
    case signalSent
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
    private let connector: any SocketConnecting

    public init(
        resolver: ProcessResolving = ProcessLookup(),
        terminator: ProcessTerminating = SystemProcessTerminator(),
        connector: any SocketConnecting = TCPPortConnector()
    ) {
        self.resolver = resolver
        self.terminator = terminator
        self.connector = connector
    }

    public func terminateAndWaitForPortRelease(
        target: KillTarget,
        timeout: TimeInterval = 3,
        pollInterval: TimeInterval = 0.2
    ) async throws {
        try Task.checkCancellation()
        try terminateAfterRevalidation(target: target)
        let deadline = ProcessInfo.processInfo.systemUptime + max(timeout, 0)
        while true {
            try Task.checkCancellation()
            let observation = Result { try resolver.info(for: target.port) }
            try Task.checkCancellation()
            let incomplete: KillError
            switch observation {
            case .failure(let error):
                incomplete = .terminationUnconfirmed(String(describing: error))
            case .success(.some(let current)):
                guard current.identity == target.identity else {
                    throw KillError.portReoccupied(port: target.port, pid: current.pid)
                }
                incomplete = .portStillListening(port: target.port)
            case .success(nil):
                if !connector.isListeningOnLocalhost(port: target.port, timeout: 0.2) {
                    try Task.checkCancellation()
                    return
                }
                incomplete = .terminationUnconfirmed("포트 \(target.port)가 응답하지만 수신 프로세스를 확인할 수 없습니다.")
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw incomplete }
            try await Task.sleep(for: .seconds(min(max(pollInterval, 0.01), remaining)))
        }
    }

    public func terminateAfterRevalidation(target: KillTarget) throws {
        let current: PortProcessInfo?
        do {
            current = try resolver.info(for: target.port)
        } catch ProcessLookupError.untrustedListeners(let port, let reasons) {
            throw KillError.untrustedListener(
                port: port,
                reasons: reasons.normalizedByResolutionOrder
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
        guard current.identity.startTime == target.identity.startTime else {
            throw KillError.processRestarted(pid: target.pid)
        }

        try Task.checkCancellation()
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
        return .signalSent
    }
}
