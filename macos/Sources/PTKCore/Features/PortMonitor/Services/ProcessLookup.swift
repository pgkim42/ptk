import Foundation

public struct PortProcessInfo: Equatable, Sendable {
    public let port: UInt16
    public let identity: VerifiedProcessIdentity

    public var pid: Int { identity.pid }
    public var processName: String { identity.processName }

    public init(port: UInt16, identity: VerifiedProcessIdentity) {
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

public enum ProcessLookupError: Error, Equatable, CustomStringConvertible {
    case lsofFailed(String)
    case processNameFailed(pid: Int, message: String)
    case ambiguousListeners(port: UInt16, pids: [Int])
    case untrustedListeners(port: UInt16, reasons: [LsofUntrustedReason])
    case processNameUnavailable(pid: Int)
    case processStartTimeUnavailable(pid: Int)
    case processChangedDuringLookup(pid: Int)

    public var description: String {
        switch self {
        case .lsofFailed(let message):
            return message
        case .processNameFailed(let pid, let message):
            return "process name lookup failed for PID \(pid): \(message)"
        case .ambiguousListeners(let port, let pids):
            let pidList = pids.sorted().map(String.init).joined(separator: ", ")
            return "ambiguous listeners for port \(port): PIDs \(pidList)"
        case .untrustedListeners(let port, let reasons):
            let reasonList = reasons.normalizedByResolutionOrder
                .map { String(describing: $0) }
                .joined(separator: ", ")
            return "untrusted listeners for port \(port): \(reasonList)"
        case .processNameUnavailable(let pid):
            return "process name unavailable for PID \(pid)"
        case .processStartTimeUnavailable(let pid):
            return "process start time unavailable for PID \(pid); refresh and try again"
        case .processChangedDuringLookup(let pid):
            return "process changed during lookup for PID \(pid); refresh and try again"
        }
    }
}

public struct ProcessLookup: Sendable {
    private let runner: ProcessRunning
    private let parser: LsofParser
    private let startTime: @Sendable (Int) -> ProcessStartTime?

    public init(runner: ProcessRunning = SystemProcessRunner(), parser: LsofParser = LsofParser()) {
        self.init(runner: runner, parser: parser, startTime: { ProcessStartTime.read(pid: $0) })
    }

    public init(
        runner: ProcessRunning,
        parser: LsofParser = LsofParser(),
        startTime: @escaping @Sendable (Int) -> ProcessStartTime?
    ) {
        self.runner = runner
        self.parser = parser
        self.startTime = startTime
    }

    public func listeningSnapshot() throws -> LsofSnapshot {
        let result: ProcessRunResult
        do {
            result = try runner.run(
                "lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"],
                timeout: 2
            )
        } catch {
            throw ProcessLookupError.lsofFailed(String(describing: error))
        }
        guard result.succeeded else {
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 1, stdout.isEmpty, stderr.isEmpty {
                return LsofSnapshot(records: [])
            }
            throw ProcessLookupError.lsofFailed(stderr)
        }
        return parser.parse(result.stdout)
    }


    public func processName(pid: Int) throws -> String? {
        guard pid > 0 else { return nil }

        let result: ProcessRunResult
        do {
            result = try runner.run(
                "ps",
                arguments: ["-p", "\(pid)", "-o", "comm="],
                timeout: 1
            )
        } catch {
            throw ProcessLookupError.processNameFailed(
                pid: pid,
                message: String(describing: error)
            )
        }

        guard result.succeeded else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func info(for port: UInt16) throws -> PortProcessInfo? {
        try info(for: port, using: listeningSnapshot())
    }

    public func info(for port: UInt16, using snapshot: LsofSnapshot) throws -> PortProcessInfo? {
        let pid: Int
        switch snapshot.resolution(for: port) {
        case .absent:
            return nil
        case .verified(let verifiedPID):
            pid = verifiedPID
        case .ambiguous(let pids):
            throw ProcessLookupError.ambiguousListeners(port: port, pids: pids.sorted())
        case .untrusted(let reasons):
            throw ProcessLookupError.untrustedListeners(
                port: port,
                reasons: reasons.normalizedByResolutionOrder
            )
        }

        guard let before = startTime(pid) else {
            throw ProcessLookupError.processStartTimeUnavailable(pid: pid)
        }
        guard let processName = try processName(pid: pid) else {
            throw ProcessLookupError.processNameUnavailable(pid: pid)
        }
        guard let after = startTime(pid) else {
            throw ProcessLookupError.processStartTimeUnavailable(pid: pid)
        }
        guard before == after else {
            throw ProcessLookupError.processChangedDuringLookup(pid: pid)
        }
        guard let identity = VerifiedProcessIdentity(pid: pid, processName: processName, startTime: after) else {
            throw ProcessLookupError.processNameUnavailable(pid: pid)
        }
        return PortProcessInfo(port: port, identity: identity)
    }
}
