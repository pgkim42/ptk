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

    init(port: UInt16, pid: Int, processName: String) {
        self.init(
            port: port,
            identity: VerifiedProcessIdentity(pid: pid, processName: processName)!
        )
    }
}

public enum ProcessLookupError: Error, Equatable, CustomStringConvertible {
    case lsofFailed(String)
    case processNameFailed(pid: Int, message: String)
    case ambiguousListeners(port: UInt16, pids: [Int])
    case untrustedListeners(port: UInt16, reasons: [LsofUntrustedReason])
    case processNameUnavailable(pid: Int)

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
            let reasonList = normalizedUntrustedReasons(reasons)
                .map { String(describing: $0) }
                .joined(separator: ", ")
            return "untrusted listeners for port \(port): \(reasonList)"
        case .processNameUnavailable(let pid):
            return "process name unavailable for PID \(pid)"
        }
    }
}

public struct ProcessLookup: Sendable {
    private let runner: ProcessRunning
    private let parser: LsofParser

    public init(runner: ProcessRunning = SystemProcessRunner(), parser: LsofParser = LsofParser()) {
        self.runner = runner
        self.parser = parser
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
            throw ProcessLookupError.lsofFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parser.parse(result.stdout)
    }

    public func listeningPortPIDMap() throws -> [UInt16: Set<Int>] {
        let snapshot = try listeningSnapshot()
        var output: [UInt16: Set<Int>] = [:]
        for port in Set(snapshot.records.compactMap(\.port)).sorted() {
            switch snapshot.resolution(for: port) {
            case .verified(let pid):
                output[port] = [pid]
            case .ambiguous(let pids):
                output[port] = Set(pids)
            case .absent, .untrusted:
                break
            }
        }
        return output
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
                reasons: normalizedUntrustedReasons(reasons)
            )
        }

        guard
            let processName = try processName(pid: pid),
            let identity = VerifiedProcessIdentity(pid: pid, processName: processName)
        else {
            throw ProcessLookupError.processNameUnavailable(pid: pid)
        }
        return PortProcessInfo(port: port, identity: identity)
    }
}

private func normalizedUntrustedReasons(
    _ reasons: [LsofUntrustedReason]
) -> [LsofUntrustedReason] {
    Array(Set(reasons)).sorted {
        untrustedReasonOrder($0) < untrustedReasonOrder($1)
    }
}

private func untrustedReasonOrder(_ reason: LsofUntrustedReason) -> Int {
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
