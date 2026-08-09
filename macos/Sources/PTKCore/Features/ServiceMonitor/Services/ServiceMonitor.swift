import Foundation

public enum ServiceState: Equatable, Sendable {
    case running
    case stopped
    case unavailable

    public var label: String {
        switch self {
        case .running: "실행 중"
        case .stopped: "중지됨"
        case .unavailable: "확인 불가"
        }
    }
}

public enum ServiceGroup: String, Equatable, Sendable {
    case builtIn
    case custom

    public var label: String {
        switch self {
        case .builtIn: "기본 서비스"
        case .custom: "사용자 서비스"
        }
    }
}

public enum ServiceKind: Equatable, Sendable {
    case dockerDaemon
    case databasePort
}



public struct ServiceStatus: Equatable, Sendable {
    public let name: String
    public let detail: String
    public let state: ServiceState
    public let group: ServiceGroup
    public let kind: ServiceKind

    public init(
        name: String,
        detail: String,
        state: ServiceState,
        group: ServiceGroup = .builtIn,
        kind: ServiceKind? = nil
    ) {
        self.name = name
        self.detail = detail
        self.state = state
        self.group = group
        self.kind = kind ?? (group == .builtIn && name == "Docker" ? .dockerDaemon : .databasePort)
    }

    public var displayIdentity: String {
        "\(group.rawValue)-\(kind)-\(name.lowercased())-\(detail)"
    }

    public var displayText: String {
        "\(name) · \(detail) · \(state.label)"
    }
}

public struct DockerPublishedPort: Equatable, Hashable, Sendable {
    public let hostAddress: String?
    public let hostPort: String
    public let containerPort: String
    public let transportProtocol: String?
    public let sortPort: UInt16

    public init(
        hostAddress: String? = nil,
        hostPort: String,
        containerPort: String,
        transportProtocol: String? = nil,
        sortPort: UInt16
    ) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.transportProtocol = transportProtocol?.lowercased()
        self.sortPort = sortPort
    }

    public var displayText: String {
        let protocolSuffix = transportProtocol.map { "/\($0)" } ?? ""
        return "\(displayHost):\(hostPort) -> \(containerPort)\(protocolSuffix)"
    }

    public var localhostURLString: String? {
        guard
            transportProtocol == "tcp",
            UInt16(hostPort) != nil,
            isLocalhostBinding
        else { return nil }
        return "http://localhost:\(hostPort)"
    }

    private var isLocalhostBinding: Bool {
        guard let hostAddress else { return false }
        return ["0.0.0.0", "127.0.0.1", "::", "::1", "localhost"]
            .contains(hostAddress.lowercased())
    }

    private var displayHost: String {
        switch bindingScope {
        case "wildcard": return "*"
        case "loopback": return "localhost"
        case let scope where scope.hasPrefix("remote:"):
            let address = String(scope.dropFirst("remote:".count))
            return address.contains(":") ? "[\(address)]" : address
        default: return "host"
        }
    }

    fileprivate var presentationIdentity: String {
        "\(bindingScope)|\(hostPort)|\(containerPort)|\(transportProtocol ?? "")"
    }

    private var bindingScope: String {
        guard let address = hostAddress?.lowercased() else { return "unspecified" }
        if ["0.0.0.0", "::"].contains(address) { return "wildcard" }
        if ["127.0.0.1", "::1", "localhost"].contains(address) { return "loopback" }
        return "remote:\(address)"
    }

    fileprivate var sortIdentity: String {
        "\(hostAddress ?? "")|\(hostPort)|\(containerPort)|\(transportProtocol ?? "")"
    }
}

public struct DockerPortCopyCandidate: Equatable, Hashable, Sendable {
    public let label: String
    public let urlString: String

    public init(label: String, urlString: String) {
        self.label = label
        self.urlString = urlString
    }
}


public struct DockerContainerPublishedPorts: Equatable, Identifiable, Sendable {
    public let name: String
    public let publishedPorts: [DockerPublishedPort]

    public var id: String { name }

    public init(name: String, publishedPorts: [DockerPublishedPort]) {
        self.name = name
        self.publishedPorts = publishedPorts.sorted { lhs, rhs in
            if lhs.sortPort == rhs.sortPort {
                return lhs.sortIdentity < rhs.sortIdentity
            }
            return lhs.sortPort < rhs.sortPort
        }
    }

    public var lowestHostPort: UInt16 {
        publishedPorts.map(\.sortPort).min() ?? UInt16.max
    }
}

public struct DockerContainerPortRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let isSummary: Bool
    public let copyCandidates: [DockerPortCopyCandidate]

    public init(
        id: String,
        name: String,
        detail: String,
        isSummary: Bool = false,
        copyCandidates: [DockerPortCopyCandidate] = []
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.isSummary = isSummary
        self.copyCandidates = copyCandidates
    }

    public static func displayRows(
        for containers: [DockerContainerPublishedPorts],
        maxContainers: Int = 5,
        maxMappingsPerContainer: Int = 3
    ) -> [DockerContainerPortRow] {
        let sortedContainers = containers.sorted { lhs, rhs in
            if lhs.lowestHostPort == rhs.lowestHostPort {
                return lhs.name < rhs.name
            }
            return lhs.lowestHostPort < rhs.lowestHostPort
        }
        let visibleContainers = sortedContainers.prefix(maxContainers)
        var rows = visibleContainers.map { container in
            DockerContainerPortRow(
                id: "container-\(container.name)",
                name: container.name,
                detail: portSummary(for: container.publishedPorts, maxMappings: maxMappingsPerContainer),
                copyCandidates: copyCandidates(for: container.publishedPorts, maxMappings: maxMappingsPerContainer)
            )
        }
        let hiddenCount = sortedContainers.count - visibleContainers.count
        if hiddenCount > 0 {
            rows.append(DockerContainerPortRow(
                id: "container-more-\(hiddenCount)",
                name: "+\(hiddenCount) more",
                detail: "\(hiddenCount) hidden container\(hiddenCount == 1 ? "" : "s")",
                isSummary: true
            ))
        }
        return rows
    }

    private static func portSummary(for ports: [DockerPublishedPort], maxMappings: Int) -> String {
        let displayPorts = uniqueDisplayPorts(ports)
        var parts = displayPorts.prefix(maxMappings).map(\.displayText)
        let hiddenCount = displayPorts.count - parts.count
        if hiddenCount > 0 {
            parts.append("+\(hiddenCount)")
        }
        return parts.joined(separator: ", ")
    }

    private static func copyCandidates(for ports: [DockerPublishedPort], maxMappings: Int) -> [DockerPortCopyCandidate] {
        let displayPorts = uniqueDisplayPorts(ports)
        guard displayPorts.count <= maxMappings else { return [] }
        let candidates = displayPorts.compactMap { port -> DockerPortCopyCandidate? in
            guard let urlString = port.localhostURLString else { return nil }
            return DockerPortCopyCandidate(label: port.hostPort, urlString: urlString)
        }
        guard candidates.count == 1, candidates.count == displayPorts.count else { return [] }
        return candidates
    }

    private static func uniqueDisplayPorts(_ ports: [DockerPublishedPort]) -> [DockerPublishedPort] {
        var identities: Set<String> = []
        return ports.filter { identities.insert($0.presentationIdentity).inserted }
    }
}

public struct ServiceSnapshot: Equatable, Sendable {
    public let statuses: [ServiceStatus]
    public let dockerContainerRows: [DockerContainerPortRow]

    public init(statuses: [ServiceStatus], dockerContainerRows: [DockerContainerPortRow] = []) {
        self.statuses = statuses
        self.dockerContainerRows = dockerContainerRows
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
    case launchFailed(String)
    case timedOut
    case outputLimitExceeded(streams: Set<OwnedHelperStream>)
    case pipeDrainTimedOut
    case commandFailed(exitCode: Int32)
}

public struct DockerPublishedPortParser: Sendable {
    public init() {}

    public func parse(_ output: String) -> [DockerContainerPublishedPorts] {
        output.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap(parseLine)
            .sorted { lhs, rhs in
                if lhs.lowestHostPort == rhs.lowestHostPort {
                    return lhs.name < rhs.name
                }
                return lhs.lowestHostPort < rhs.lowestHostPort
            }
    }

    private func parseLine(_ line: Substring) -> DockerContainerPublishedPorts? {
        let columns = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard columns.count == 2 else { return nil }
        let name = String(columns[0])
        let portsText = columns[1]
        guard !name.isEmpty, !portsText.isEmpty else { return nil }

        var seen = Set<DockerPublishedPort>()
        let publishedPorts = portsText
            .split(separator: ",")
            .compactMap { parsePortSegment($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { seen.insert($0).inserted }

        guard !publishedPorts.isEmpty else { return nil }
        return DockerContainerPublishedPorts(name: name, publishedPorts: publishedPorts)
    }

    private func parsePortSegment(_ segment: String) -> DockerPublishedPort? {
        guard let arrowRange = segment.range(of: "->") else { return nil }
        let hostSide = String(segment[..<arrowRange.lowerBound])
        let containerSide = String(segment[arrowRange.upperBound...])
        guard
            let hostEndpoint = publishedHostEndpoint(from: hostSide),
            let containerEndpoint = containerEndpoint(from: containerSide),
            let sortPort = lowerBoundPort(from: hostEndpoint.port)
        else { return nil }

        return DockerPublishedPort(
            hostAddress: hostEndpoint.address,
            hostPort: hostEndpoint.port,
            containerPort: containerEndpoint.port,
            transportProtocol: containerEndpoint.transportProtocol,
            sortPort: sortPort
        )
    }

    private func publishedHostEndpoint(from hostSide: String) -> (address: String?, port: String)? {
        let address: String?
        let port: String
        if hostSide.hasPrefix("["), let bracketIndex = hostSide.firstIndex(of: "]") {
            let portStart = hostSide.index(after: bracketIndex)
            guard portStart < hostSide.endIndex, hostSide[portStart] == ":" else { return nil }
            address = String(hostSide[hostSide.index(after: hostSide.startIndex)..<bracketIndex])
            port = String(hostSide[hostSide.index(after: portStart)...])
        } else if let colonIndex = hostSide.lastIndex(of: ":") {
            let parsedAddress = String(hostSide[..<colonIndex])
            address = parsedAddress.isEmpty ? nil : parsedAddress
            port = String(hostSide[hostSide.index(after: colonIndex)...])
        } else {
            address = nil
            port = hostSide
        }
        guard lowerBoundPort(from: port) != nil else { return nil }
        return (address, port)
    }

    private func containerEndpoint(from containerSide: String) -> (port: String, transportProtocol: String?)? {
        let parts = containerSide.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let port = parts.first.map(String.init) ?? containerSide
        guard lowerBoundPort(from: port) != nil else { return nil }
        let transportProtocol = parts.count == 2 && !parts[1].isEmpty
            ? String(parts[1]).lowercased()
            : nil
        return (port, transportProtocol)
    }

    private func lowerBoundPort(from text: String) -> UInt16? {
        let lowerBound = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        return UInt16(lowerBound)
    }
}

public struct SystemServiceCommandRunner: ServiceCommandRunning {
    private let helperRunner: OwnedHelperRunner
    private let environmentOverride: [String: String]?

    public init(processFactory: @escaping OwnedHelperRunner.ProcessFactory = { Process() }) {
        helperRunner = OwnedHelperRunner(processFactory: processFactory)
        environmentOverride = nil
    }

    init(
        processFactory: @escaping OwnedHelperRunner.ProcessFactory,
        environment: [String: String]
    ) {
        helperRunner = OwnedHelperRunner(processFactory: processFactory)
        environmentOverride = environment
    }

    public func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environmentPath: String
    ) throws -> ServiceCommandResult {
        let inheritedEnvironment = environmentOverride ?? ProcessInfo.processInfo.environment
        let environment = inheritedEnvironment.merging(["PATH": environmentPath]) { _, new in new }
        let configuration = OwnedHelperConfiguration(
            timeout: timeout,
            outputLimit: OwnedHelperConfiguration.defaultOutputLimit,
            terminationGrace: 0.25,
            postExitDrainGrace: 0.25
        )

        do {
            let result = try helperRunner.run(
                "/usr/bin/env",
                arguments: [executable] + arguments,
                environment: environment,
                configuration: configuration
            )
            return ServiceCommandResult(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr
            )
        } catch let error as OwnedHelperError {
            switch error {
            case .launchFailed(let message):
                throw ServiceCommandError.launchFailed(message)
            case .timedOut:
                throw ServiceCommandError.timedOut
            case .outputLimitExceeded(let streams):
                throw ServiceCommandError.outputLimitExceeded(streams: streams)
            case .pipeDrainTimedOut:
                throw ServiceCommandError.pipeDrainTimedOut
            }
        }
    }
}

public protocol ServiceSocketChecking: SocketConnecting {}

public struct TCPServiceSocketChecker: ServiceSocketChecking {
    private let connector: TCPPortConnector

    public init() {
        connector = TCPPortConnector()
    }

    public func isListening(host: String, port: UInt16, timeout: TimeInterval = 0.2) -> Bool {
        connector.isListening(host: host, port: port, timeout: timeout)
    }
}

public struct DatabaseEndpoint: Equatable, Identifiable, Codable, Sendable {
    public let name: String
    public let port: UInt16

    public var id: String { "\(name.lowercased())-\(port)" }

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

    public func scanWithDetails() -> ServiceSnapshot {
        var docker = dockerStatus()
        var dockerContainerRows: [DockerContainerPortRow] = []

        if docker.state == .running {
            do {
                dockerContainerRows = try collectDockerContainerRows()
            } catch ServiceCommandError.timedOut {
                docker = ServiceStatus(name: "Docker", detail: "Details timeout", state: .unavailable, kind: .dockerDaemon)
            } catch ServiceCommandError.commandFailed(let exitCode) {
                docker = ServiceStatus(name: "Docker", detail: "Daemon; details failed (\(exitCode))", state: .running, kind: .dockerDaemon)
            } catch {
                docker = ServiceStatus(name: "Docker", detail: "Details unavailable", state: .unavailable, kind: .dockerDaemon)
            }
        }

        return ServiceSnapshot(statuses: [docker] + databaseStatuses(), dockerContainerRows: dockerContainerRows)
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
            return ServiceStatus(name: "Docker", detail: "Daemon timeout", state: .unavailable, kind: .dockerDaemon)
        } catch {
            return ServiceStatus(name: "Docker", detail: "Command unavailable", state: .unavailable, kind: .dockerDaemon)
        }
        if result.succeeded {
            return ServiceStatus(name: "Docker", detail: "Daemon", state: .running, kind: .dockerDaemon)
        }
        if result.exitCode == 127 || result.stderr.localizedCaseInsensitiveContains("no such file") {
            return ServiceStatus(name: "Docker", detail: "Command unavailable", state: .unavailable, kind: .dockerDaemon)
        }
        return ServiceStatus(name: "Docker", detail: "Daemon", state: .stopped, kind: .dockerDaemon)
    }

    private func collectDockerContainerRows() throws -> [DockerContainerPortRow] {
        let result = try runner.run(
            "docker",
            arguments: ["ps", "--format", "{{.Names}}\t{{.Ports}}"],
            timeout: dockerCommandTimeout,
            environmentPath: ServiceMonitor.dockerEnvironmentPath
        )
        guard result.succeeded else { throw ServiceCommandError.commandFailed(exitCode: result.exitCode) }
        let containers = DockerPublishedPortParser().parse(result.stdout)
        return DockerContainerPortRow.displayRows(for: containers)
    }

    public func databaseStatuses(group: ServiceGroup = .builtIn) -> [ServiceStatus] {
        databaseEndpoints.map { endpoint in
            ServiceStatus(
                name: endpoint.name,
                detail: "Port \(endpoint.port)",
                state: connector.isListeningOnLocalhost(port: endpoint.port, timeout: timeout) ? .running : .stopped,
                group: group
            )
        }
    }
}
