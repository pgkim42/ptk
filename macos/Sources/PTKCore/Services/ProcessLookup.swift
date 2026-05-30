public struct PortProcessInfo: Equatable, Sendable {
    public let port: UInt16
    public let pid: Int
    public let processName: String?

    public init(port: UInt16, pid: Int, processName: String?) {
        self.port = port
        self.pid = pid
        self.processName = processName
    }
}

public enum ProcessLookupError: Error, Equatable, CustomStringConvertible {
    case lsofFailed(String)

    public var description: String {
        switch self {
        case .lsofFailed(let message): message
        }
    }
}

public struct ProcessLookup {
    private let runner: ProcessRunning
    private let parser: LsofParser

    public init(runner: ProcessRunning = SystemProcessRunner(), parser: LsofParser = LsofParser()) {
        self.runner = runner
        self.parser = parser
    }

    public func listeningPortPIDMap() throws -> [UInt16: Int] {
        let result = try runner.run("lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"])
        guard result.succeeded else {
            throw ProcessLookupError.lsofFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parser.parseListeningPIDMap(result.stdout)
    }

    public func processName(pid: Int) -> String? {
        guard pid > 0 else { return nil }
        guard let result = try? runner.run("ps", arguments: ["-p", "\(pid)", "-o", "comm="]), result.succeeded else {
            return nil
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func info(for port: UInt16) throws -> PortProcessInfo? {
        let map = try listeningPortPIDMap()
        guard let pid = map[port] else { return nil }
        return PortProcessInfo(port: port, pid: pid, processName: processName(pid: pid))
    }
}
