import Foundation
import Darwin

public enum ServiceState: Equatable, Sendable {
    case running
    case stopped
    case unavailable

    public var label: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        case .unavailable: "Unavailable"
        }
    }
}

public struct ServiceStatus: Equatable, Sendable {
    public let name: String
    public let detail: String
    public let state: ServiceState

    public init(name: String, detail: String, state: ServiceState) {
        self.name = name
        self.detail = detail
        self.state = state
    }

    public var displayText: String {
        "\(name) · \(detail) · \(state.label)"
    }
}

public struct ServiceCommandResult: Equatable, Sendable {
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

public protocol ServiceCommandRunning: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environmentPath: String
    ) throws -> ServiceCommandResult
}

public enum ServiceCommandError: Error, Equatable, Sendable {
    case timedOut
}

public protocol ServiceProcess: AnyObject, Sendable {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    var environment: [String: String]? { get set }
    var standardOutput: Any? { get set }
    var standardError: Any? { get set }
    var terminationStatus: Int32 { get }

    func run() throws
    func waitUntilExit()
    func terminate()
}

extension Process: ServiceProcess {}

public struct SystemServiceCommandRunner: ServiceCommandRunning {
    private let processFactory: @Sendable () -> any ServiceProcess

    public init(processFactory: @escaping @Sendable () -> any ServiceProcess = { Process() }) {
        self.processFactory = processFactory
    }

    public func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environmentPath: String
    ) throws -> ServiceCommandResult {
        let process = processFactory()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["PATH": environmentPath]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
            }
            throw ServiceCommandError.timedOut
        }

        return ServiceCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

public protocol ServiceSocketChecking: Sendable {
    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool
}

public struct TCPServiceSocketChecker: ServiceSocketChecking {
    public init() {}

    public func isListening(host: String, port: UInt16, timeout: TimeInterval = 0.2) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

public struct DatabaseEndpoint: Equatable, Sendable {
    public let name: String
    public let port: UInt16

    public init(name: String, port: UInt16) {
        self.name = name
        self.port = port
    }
}

public struct ServiceMonitor: Sendable {
    public static let dockerEnvironmentPath = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/Applications/Docker.app/Contents/Resources/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ].joined(separator: ":")

    public static let defaultDatabaseEndpoints: [DatabaseEndpoint] = [
        DatabaseEndpoint(name: "PostgreSQL", port: 5432),
        DatabaseEndpoint(name: "MySQL", port: 3306),
        DatabaseEndpoint(name: "Redis", port: 6379),
        DatabaseEndpoint(name: "MongoDB", port: 27017)
    ]

    private let runner: any ServiceCommandRunning
    private let connector: any ServiceSocketChecking
    private let databaseEndpoints: [DatabaseEndpoint]
    private let timeout: TimeInterval
    private let dockerCommandTimeout: TimeInterval

    public init(
        runner: any ServiceCommandRunning = SystemServiceCommandRunner(),
        connector: any ServiceSocketChecking = TCPServiceSocketChecker(),
        databaseEndpoints: [DatabaseEndpoint] = ServiceMonitor.defaultDatabaseEndpoints,
        timeout: TimeInterval = 0.2,
        dockerCommandTimeout: TimeInterval = 1
    ) {
        self.runner = runner
        self.connector = connector
        self.databaseEndpoints = databaseEndpoints
        self.timeout = max(timeout, 0.05)
        self.dockerCommandTimeout = max(dockerCommandTimeout, 0.1)
    }

    public func scan() -> [ServiceStatus] {
        [dockerStatus()] + databaseStatuses()
    }

    public func dockerStatus() -> ServiceStatus {
        let result: ServiceCommandResult
        do {
            result = try runner.run(
                "docker",
                arguments: ["info"],
                timeout: dockerCommandTimeout,
                environmentPath: ServiceMonitor.dockerEnvironmentPath
            )
        } catch ServiceCommandError.timedOut {
            return ServiceStatus(name: "Docker", detail: "Daemon timeout", state: .unavailable)
        } catch {
            return ServiceStatus(name: "Docker", detail: "Command unavailable", state: .unavailable)
        }
        if result.succeeded {
            return ServiceStatus(name: "Docker", detail: "Daemon", state: .running)
        }
        if result.exitCode == 127 || result.stderr.localizedCaseInsensitiveContains("no such file") {
            return ServiceStatus(name: "Docker", detail: "Command unavailable", state: .unavailable)
        }
        return ServiceStatus(name: "Docker", detail: "Daemon", state: .stopped)
    }

    public func databaseStatuses(host: String = "127.0.0.1") -> [ServiceStatus] {
        databaseEndpoints.map { endpoint in
            ServiceStatus(
                name: endpoint.name,
                detail: "Port \(endpoint.port)",
                state: connector.isListening(host: host, port: endpoint.port, timeout: timeout) ? .running : .stopped
            )
        }
    }
}
