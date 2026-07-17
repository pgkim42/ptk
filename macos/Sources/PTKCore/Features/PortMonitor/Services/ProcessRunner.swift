import Foundation

public struct ProcessRunResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

public protocol ProcessRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult
}

public enum ProcessRunnerError: Error, Equatable, CustomStringConvertible, Sendable {
    case launchFailed(String)
    case timedOut
    case outputLimitExceeded(streams: Set<OwnedHelperStream>)
    case pipeDrainTimedOut

    public var description: String {
        switch self {
        case .launchFailed(let message):
            return message
        case .timedOut:
            return "process timed out"
        case .outputLimitExceeded(let streams):
            let names = streams.map(\.rawValue).sorted().joined(separator: ", ")
            return "process output limit exceeded: \(names)"
        case .pipeDrainTimedOut:
            return "process output pipes did not close after exit"
        }
    }
}

public struct SystemProcessRunner: ProcessRunning {
    private let helperRunner: OwnedHelperRunner

    public init(helperRunner: OwnedHelperRunner = OwnedHelperRunner()) {
        self.helperRunner = helperRunner
    }

    public func run(_ executable: String, arguments: [String]) throws -> ProcessRunResult {
        try run(executable, arguments: arguments, timeout: 2)
    }

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        do {
            let result = try helperRunner.run(
                "/usr/bin/env",
                arguments: [executable] + arguments,
                configuration: OwnedHelperConfiguration(timeout: timeout)
            )
            return ProcessRunResult(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr
            )
        } catch let error as OwnedHelperError {
            throw map(error)
        }
    }

    private func map(_ error: OwnedHelperError) -> ProcessRunnerError {
        switch error {
        case .launchFailed(let message):
            return .launchFailed(message)
        case .timedOut:
            return .timedOut
        case .outputLimitExceeded(let streams):
            return .outputLimitExceeded(streams: streams)
        case .pipeDrainTimedOut:
            return .pipeDrainTimedOut
        }
    }
}
