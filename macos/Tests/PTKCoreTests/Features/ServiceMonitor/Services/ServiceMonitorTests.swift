import Foundation
import Darwin
import Testing
@testable import PTKCore

@Suite struct ServiceMonitorTests {
    @Test func dockerRunningWhenDockerInfoSucceeds() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n")
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        #expect(monitor.dockerStatus() == ServiceStatus(name: "Docker", detail: "Daemon", state: .running))
    }

    @Test func dockerUnavailableWhenDockerCommandMissing() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 127, stdout: "", stderr: "env: docker: No such file or directory")
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        #expect(monitor.dockerStatus() == ServiceStatus(name: "Docker", detail: "Command unavailable", state: .unavailable))
    }

    @Test func dockerStoppedWhenDockerInfoFails() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 1, stdout: "", stderr: "Cannot connect to the Docker daemon")
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        #expect(monitor.dockerStatus() == ServiceStatus(name: "Docker", detail: "Daemon", state: .stopped))
    }

    @Test func dockerTimeoutIsUnavailable() {
        let runner = FakeServiceCommandRunner(error: ServiceCommandError.timedOut)
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        #expect(monitor.dockerStatus() == ServiceStatus(name: "Docker", detail: "Daemon timeout", state: .unavailable))
    }

    @Test func dockerHelperLifecycleFailuresAreCommandUnavailable() {
        let errors: [ServiceCommandError] = [
            .launchFailed("launch failed"),
            .outputLimitExceeded(streams: [.stdout]),
            .pipeDrainTimedOut
        ]

        for error in errors {
            let runner = FakeServiceCommandRunner(error: error)
            let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

            #expect(monitor.dockerStatus() == ServiceStatus(
                name: "Docker",
                detail: "Command unavailable",
                state: .unavailable
            ))
        }
    }

    @Test func dockerCommandUsesControlledPath() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 0, stdout: "")
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        _ = monitor.dockerStatus()

        #expect(runner.calls == [ServiceCommandCall(
            executable: "docker",
            arguments: ["info"],
            timeout: 1,
            environmentPath: ServiceMonitor.dockerEnvironmentPath
        )])
        #expect(ServiceMonitor.dockerEnvironmentPath.contains("/opt/homebrew/bin"))
        #expect(ServiceMonitor.dockerEnvironmentPath.contains("/Applications/Docker.app/Contents/Resources/bin"))
    }

    @Test func dockerPublishedPortParserKeepsOnlyHostPublishedPorts() {
        let output = """
        api\t0.0.0.0:4000->4000/tcp, 127.0.0.1:9229->9229/tcp, 8080/tcp
        web\t[::]:3000->80/tcp, :::3443->443/tcp
        worker\t9000/tcp
        empty\t
        db\t127.0.0.1:5432-5433->5432-5433/tcp, 5432/tcp
        """

        let rows = DockerPublishedPortParser().parse(output)

        #expect(rows.map(\.name) == ["web", "api", "db"])
        #expect(rows[0].publishedPorts.map(\.displayText) == ["3000 -> 80", "3443 -> 443"])
        #expect(rows[1].publishedPorts.map(\.displayText) == ["4000 -> 4000", "9229 -> 9229"])
        #expect(rows[2].publishedPorts.map(\.displayText) == ["5432-5433 -> 5432-5433"])
        #expect(rows[0].publishedPorts[0].localhostURLString == "http://localhost:3000")
        #expect(rows[2].publishedPorts[0].localhostURLString == nil)
    }

    @Test func dockerPublishedPortRowsCollapseMappingsAndContainersForDisplay() {
        let containers = [
            DockerContainerPublishedPorts(name: "api", publishedPorts: [
                DockerPublishedPort(hostPort: "4000", containerPort: "4000", sortPort: 4000),
                DockerPublishedPort(hostPort: "9229", containerPort: "9229", sortPort: 9229),
                DockerPublishedPort(hostPort: "9230", containerPort: "9230", sortPort: 9230),
                DockerPublishedPort(hostPort: "9231", containerPort: "9231", sortPort: 9231)
            ]),
            DockerContainerPublishedPorts(name: "web", publishedPorts: [
                DockerPublishedPort(hostPort: "3000", containerPort: "80", sortPort: 3000)
            ]),
            DockerContainerPublishedPorts(name: "redis", publishedPorts: [
                DockerPublishedPort(hostPort: "6379", containerPort: "6379", sortPort: 6379)
            ]),
            DockerContainerPublishedPorts(name: "db", publishedPorts: [
                DockerPublishedPort(hostPort: "5432", containerPort: "5432", sortPort: 5432)
            ]),
            DockerContainerPublishedPorts(name: "mail", publishedPorts: [
                DockerPublishedPort(hostPort: "1025", containerPort: "1025", sortPort: 1025)
            ]),
            DockerContainerPublishedPorts(name: "admin", publishedPorts: [
                DockerPublishedPort(hostPort: "8080", containerPort: "8080", sortPort: 8080)
            ])
        ]

        let displayRows = DockerContainerPortRow.displayRows(for: containers)

        #expect(displayRows.map(\.name) == ["mail", "web", "api", "db", "redis", "+1 more"])
        #expect(displayRows[2].detail == "4000 -> 4000, 9229 -> 9229, 9230 -> 9230, +1")
        #expect(displayRows.last?.detail == "1 hidden container")
        #expect(displayRows[1].copyCandidates == [
            DockerPortCopyCandidate(label: "3000", urlString: "http://localhost:3000")
        ])
        #expect(displayRows[2].copyCandidates.isEmpty)
        #expect(displayRows.last?.copyCandidates.isEmpty == true)
    }

    @Test func dockerPublishedPortRowsExposeOnlyUnambiguousVisibleCopyURLs() {
        let rows = DockerContainerPortRow.displayRows(for: [
            DockerContainerPublishedPorts(name: "web", publishedPorts: [
                DockerPublishedPort(hostPort: "3000", containerPort: "80", sortPort: 3000)
            ]),
            DockerContainerPublishedPorts(name: "api", publishedPorts: [
                DockerPublishedPort(hostPort: "4000", containerPort: "4000", sortPort: 4000),
                DockerPublishedPort(hostPort: "9229", containerPort: "9229", sortPort: 9229)
            ]),
            DockerContainerPublishedPorts(name: "db", publishedPorts: [
                DockerPublishedPort(hostPort: "5432-5433", containerPort: "5432-5433", sortPort: 5432)
            ]),
            DockerContainerPublishedPorts(name: "hidden", publishedPorts: [
                DockerPublishedPort(hostPort: "5000", containerPort: "5000", sortPort: 5000),
                DockerPublishedPort(hostPort: "5001", containerPort: "5001", sortPort: 5001)
            ])
        ], maxContainers: 4, maxMappingsPerContainer: 1)

        #expect(rows.first { $0.name == "web" }?.copyCandidates == [
            DockerPortCopyCandidate(label: "3000", urlString: "http://localhost:3000")
        ])
        #expect(rows.first { $0.name == "api" }?.copyCandidates.isEmpty == true)
        #expect(rows.first { $0.name == "db" }?.copyCandidates.isEmpty == true)
        #expect(rows.first { $0.name == "hidden" }?.copyCandidates.isEmpty == true)
    }

    @Test func serviceSnapshotCollectsDockerPortsOnlyWhenDockerIsRunning() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n"),
            "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandResult(
                exitCode: 0,
                stdout: "api\t0.0.0.0:4000->4000/tcp\n"
            )
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Daemon", state: .running))
        #expect(snapshot.dockerContainerRows.map(\.name) == ["api"])
        #expect(runner.calls.map(\.arguments) == [
            ["info"],
            ["ps", "--format", "{{.Names}}\t{{.Ports}}"]
        ])
    }

    @Test func dockerPsTimeoutPublishesDetailsTimeoutWithoutRows() {
        let runner = FakeServiceCommandRunner(
            results: [
                "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n")
            ],
            errors: [
                "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandError.timedOut
            ]
        )
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Details timeout", state: .unavailable))
        #expect(snapshot.dockerContainerRows.isEmpty)
    }

    @Test func dockerPsLaunchFailureMakesDetailsUnavailableWithoutRows() {
        let runner = FakeServiceCommandRunner(
            results: [
                "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n")
            ],
            errors: [
                "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandError.launchFailed("launch failed")
            ]
        )
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Details unavailable", state: .unavailable))
        #expect(snapshot.dockerContainerRows.isEmpty)
    }

    @Test func dockerPsOutputOverflowMakesDetailsUnavailableWithoutRows() {
        let runner = FakeServiceCommandRunner(
            results: [
                "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n")
            ],
            errors: [
                "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandError.outputLimitExceeded(streams: [.stdout])
            ]
        )
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Details unavailable", state: .unavailable))
        #expect(snapshot.dockerContainerRows.isEmpty)
    }

    @Test func dockerPsPostReapDrainFailureMakesDetailsUnavailableWithoutRows() {
        let runner = FakeServiceCommandRunner(
            results: [
                "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n")
            ],
            errors: [
                "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandError.pipeDrainTimedOut
            ]
        )
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Details unavailable", state: .unavailable))
        #expect(snapshot.dockerContainerRows.isEmpty)
    }

    @Test func dockerPsNonServiceCommandErrorMakesDetailsUnavailableWithoutRows() {
        let runner = FakeServiceCommandRunner(
            results: [
                "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n")
            ],
            errors: [
                "docker ps --format {{.Names}}\t{{.Ports}}": DockerPsSentinelError.failure
            ]
        )
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Details unavailable", state: .unavailable))
        #expect(snapshot.dockerContainerRows.isEmpty)
    }

    @Test func dockerPsOrdinaryNonzeroKeepsDockerRunningWithoutParsingRows() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n"),
            "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandResult(
                exitCode: 1,
                stdout: "must-not-parse\t0.0.0.0:4000->4000/tcp\n",
                stderr: "boom"
            )
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Daemon", state: .running))
        #expect(snapshot.dockerContainerRows.isEmpty)
    }

    @Test func stoppedDockerSkipsDockerPsCollection() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 1, stdout: "", stderr: "Cannot connect to the Docker daemon")
        ])
        let monitor = ServiceMonitor(runner: runner, connector: FakeServiceSocketChecker(openPorts: []))

        let snapshot = monitor.scanWithDetails()

        #expect(snapshot.statuses.first == ServiceStatus(name: "Docker", detail: "Daemon", state: .stopped))
        #expect(snapshot.dockerContainerRows.isEmpty)
        #expect(runner.calls.map(\.arguments) == [["info"]])
    }

    @Test func systemServiceCommandRunnerReturnsPromptlyAfterTimeoutAndReapsWithOneWaiter() {
        let process = FakeOwnedHelperProcess(behavior: .ignoresTerm)
        let runner = SystemServiceCommandRunner(processFactory: { process })
        let startedAt = Date()

        let error = capturedServiceCommandError {
            _ = try runner.run(
                "docker",
                arguments: ["info"],
                timeout: 0.01,
                environmentPath: "/bin:/usr/bin"
            )
        }

        #expect(error == .timedOut)
        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(process.waitUntilExitCallCount == 1)
        #expect(process.receivedSignals == [SIGTERM, SIGKILL])
    }

    @Test func systemServiceCommandRunnerKillsTermIgnoringDirectChildPromptly() {
        let runner = SystemServiceCommandRunner()
        let startedAt = Date()

        #expect(throws: ServiceCommandError.timedOut) {
            try runner.run(
                "sh",
                arguments: ["-c", "trap '' TERM; while :; do :; done"],
                timeout: 0.05,
                environmentPath: "/bin:/usr/bin"
            )
        }
        #expect(Date().timeIntervalSince(startedAt) < 1)
    }

    @Test func systemServiceCommandRunnerMapsLaunchFailure() {
        let process = FakeOwnedHelperProcess(behavior: .launchFails)
        let runner = SystemServiceCommandRunner(processFactory: { process })

        let error = capturedServiceCommandError {
            _ = try runner.run(
                "docker",
                arguments: ["info"],
                timeout: 1,
                environmentPath: "/bin:/usr/bin"
            )
        }

        #expect(error == .launchFailed("launch failed"))
        #expect(process.waitUntilExitCallCount == 0)
    }

    @Test func systemServiceCommandRunnerMapsPerStreamOutputOverflow() {
        let oversized = Data(repeating: 0x61, count: 4 * 1_024 * 1_024 + 1)
        let process = FakeOwnedHelperProcess(
            behavior: .exits(exitCode: 0, stdout: oversized, stderr: oversized)
        )
        let runner = SystemServiceCommandRunner(processFactory: { process })

        let error = capturedServiceCommandError {
            _ = try runner.run(
                "docker",
                arguments: ["info"],
                timeout: 2,
                environmentPath: "/bin:/usr/bin"
            )
        }

        #expect(error == .outputLimitExceeded(streams: [.stdout, .stderr]))
        #expect(process.waitUntilExitCallCount == 1)
    }

    @Test func systemServiceCommandRunnerMapsPostExitPipeDrainTimeout() {
        let process = FakeOwnedHelperProcess(behavior: .holdsStdoutOpen)
        let runner = SystemServiceCommandRunner(processFactory: { process })

        let error = capturedServiceCommandError {
            _ = try runner.run(
                "docker",
                arguments: ["info"],
                timeout: 1,
                environmentPath: "/bin:/usr/bin"
            )
        }
        process.releaseHeldPipes()

        #expect(error == .pipeDrainTimedOut)
        #expect(process.waitUntilExitCallCount == 1)
    }

    @Test func systemServiceCommandRunnerExactlyReplacesHostileInheritedPathAndReturnsCapturedResult() throws {
        let process = FakeOwnedHelperProcess(
            behavior: .exits(
                exitCode: 7,
                stdout: Data("output".utf8),
                stderr: Data("warning".utf8)
            )
        )
        let hostilePath = "/hostile/bin:$(touch /tmp/ptk-must-not-run)"
        let inheritedEnvironment = [
            "PATH": hostilePath,
            "PTK_PRESERVED": "yes"
        ]
        let runner = SystemServiceCommandRunner(
            processFactory: { process },
            environment: inheritedEnvironment
        )
        let controlledPath = "/controlled/bin:/usr/bin"

        let result = try runner.run(
            "docker",
            arguments: ["info"],
            timeout: 1,
            environmentPath: controlledPath
        )

        #expect(process.executableURL?.path == "/usr/bin/env")
        #expect(process.arguments == ["docker", "info"])
        #expect(process.environment == [
            "PATH": controlledPath,
            "PTK_PRESERVED": "yes"
        ])
        #expect(process.environment?["PATH"] == controlledPath)
        #expect(process.environment?["PATH"]?.contains(hostilePath) == false)
        #expect(result == ServiceCommandResult(exitCode: 7, stdout: "output", stderr: "warning"))
    }

    @Test func databaseStatusesReflectKnownPorts() {
        let monitor = ServiceMonitor(
            runner: FakeServiceCommandRunner(),
            connector: FakeServiceSocketChecker(openPorts: [5432, 6379])
        )

        #expect(monitor.databaseStatuses() == [
            ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .running),
            ServiceStatus(name: "MySQL", detail: "Port 3306", state: .stopped),
            ServiceStatus(name: "Redis", detail: "Port 6379", state: .running),
            ServiceStatus(name: "MongoDB", detail: "Port 27017", state: .stopped)
        ])
    }

    @Test func databaseStatusesCanUseCustomReadOnlyEndpoints() {
        let monitor = ServiceMonitor(
            runner: FakeServiceCommandRunner(),
            connector: FakeServiceSocketChecker(openPorts: [4566, 9200]),
            databaseEndpoints: [
                DatabaseEndpoint(name: "LocalStack", port: 4566),
                DatabaseEndpoint(name: "Elasticsearch", port: 9200),
                DatabaseEndpoint(name: "RabbitMQ", port: 5672)
            ]
        )

        #expect(monitor.databaseStatuses() == [
            ServiceStatus(name: "LocalStack", detail: "Port 4566", state: .running),
            ServiceStatus(name: "Elasticsearch", detail: "Port 9200", state: .running),
            ServiceStatus(name: "RabbitMQ", detail: "Port 5672", state: .stopped)
        ])
    }

    @Test func customDatabaseStatusesCanBeGrouped() {
        let monitor = ServiceMonitor(
            runner: FakeServiceCommandRunner(),
            connector: FakeServiceSocketChecker(openPorts: [5672]),
            databaseEndpoints: [
                DatabaseEndpoint(name: "RabbitMQ", port: 5672)
            ]
        )

        #expect(monitor.databaseStatuses(group: .custom) == [
            ServiceStatus(name: "RabbitMQ", detail: "Port 5672", state: .running, group: .custom)
        ])
    }

    @Test func ipv6OnlyDatabaseListenerIsRunning() {
        let connector = RecordingServiceSocketChecker(
            openHostsByPort: [5432: ["::1"]]
        )
        let monitor = ServiceMonitor(
            runner: FakeServiceCommandRunner(),
            connector: connector,
            databaseEndpoints: [DatabaseEndpoint(name: "PostgreSQL", port: 5432)],
            timeout: 1
        )

        #expect(monitor.databaseStatuses() == [
            ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .running)
        ])
        #expect(connector.calls.map(\.host) == ["127.0.0.1", "::1"])
    }

    @Test func serviceSocketCheckerUsesSharedAbsoluteProbeBudget() {
        let clock = ServiceProbeClock()
        let connector = RecordingServiceSocketChecker(
            openHostsByPort: [5432: ["::1"]],
            elapsedByHost: ["127.0.0.1": 0.125, "::1": 0.25],
            clock: clock
        )

        let isOpen = connector.isListeningOnLocalhost(
            port: 5432,
            timeout: 1,
            now: { clock.now }
        )
        #expect(isOpen)
        #expect(connector.calls == [
            ServiceSocketProbeCall(host: "127.0.0.1", port: 5432, timeout: 0.5),
            ServiceSocketProbeCall(host: "::1", port: 5432, timeout: 0.875)
        ])
        #expect(clock.now == 0.375)
    }
}

private enum DockerPsSentinelError: Error {
    case failure
}
private final class FakeServiceCommandRunner: ServiceCommandRunning, @unchecked Sendable {
    var results: [String: ServiceCommandResult]
    var errors: [String: Error]
    var error: Error?
    var calls: [ServiceCommandCall] = []

    init(
        results: [String: ServiceCommandResult] = [:],
        errors: [String: Error] = [:],
        error: Error? = nil
    ) {
        self.results = results
        self.errors = errors
        self.error = error
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environmentPath: String) throws -> ServiceCommandResult {
        calls.append(ServiceCommandCall(executable: executable, arguments: arguments, timeout: timeout, environmentPath: environmentPath))
        let key = ([executable] + arguments).joined(separator: " ")
        if let commandError = errors[key] { throw commandError }
        if let error { throw error }
        return results[key] ?? ServiceCommandResult(exitCode: 1, stdout: "", stderr: "missing fake result")
    }
}

private struct ServiceCommandCall: Equatable {
    let executable: String
    let arguments: [String]
    let timeout: TimeInterval
    let environmentPath: String
}

private struct FakeServiceSocketChecker: ServiceSocketChecking {
    let openPorts: Set<UInt16>

    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        openPorts.contains(port)
    }
}

private struct ServiceSocketProbeCall: Equatable {
    let host: String
    let port: UInt16
    let timeout: TimeInterval
}

private final class ServiceProbeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: TimeInterval = 0

    var now: TimeInterval {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            storedNow += interval
        }
    }
}

private final class RecordingServiceSocketChecker: ServiceSocketChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let openHostsByPort: [UInt16: Set<String>]
    private let elapsedByHost: [String: TimeInterval]
    private let clock: ServiceProbeClock?
    private var storedCalls: [ServiceSocketProbeCall] = []

    init(
        openHostsByPort: [UInt16: Set<String>] = [:],
        elapsedByHost: [String: TimeInterval] = [:],
        clock: ServiceProbeClock? = nil
    ) {
        self.openHostsByPort = openHostsByPort
        self.elapsedByHost = elapsedByHost
        self.clock = clock
    }

    var calls: [ServiceSocketProbeCall] {
        lock.withLock { storedCalls }
    }

    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        lock.withLock {
            storedCalls.append(
                ServiceSocketProbeCall(host: host, port: port, timeout: timeout)
            )
        }

        let elapsed = elapsedByHost[host] ?? 0
        clock?.advance(by: min(elapsed, max(timeout, 0)))
        return openHostsByPort[port]?.contains(host) == true && elapsed <= timeout
    }
}

private final class FakeOwnedHelperProcess: OwnedHelperProcess, @unchecked Sendable {
    enum Behavior {
        case exits(exitCode: Int32, stdout: Data, stderr: Data)
        case launchFails
        case ignoresTerm
        case holdsStdoutOpen
    }

    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?

    private let behavior: Behavior
    private let condition = NSCondition()
    private var heldOutput: FileHandle?
    private var killed = false
    private var signals: [Int32] = []
    private var waitCallCount = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var terminationStatus: Int32 {
        if case .exits(let exitCode, _, _) = behavior {
            return exitCode
        }
        return 0
    }

    let processIdentifier: Int32 = 42

    var waitUntilExitCallCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return waitCallCount
    }

    var receivedSignals: [Int32] {
        condition.lock()
        defer { condition.unlock() }
        return signals
    }

    func run() throws {
        switch behavior {
        case .exits(_, let stdout, let stderr):
            write(stdout, to: standardOutput)
            write(stderr, to: standardError)
        case .launchFails:
            throw NSError(
                domain: "FakeOwnedHelperProcess",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "launch failed"]
            )
        case .ignoresTerm:
            break
        case .holdsStdoutOpen:
            guard
                let pipe = standardOutput as? Pipe,
                let duplicate = duplicateFileHandle(pipe.fileHandleForWriting)
            else {
                throw NSError(
                    domain: "FakeOwnedHelperProcess",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "failed to retain output pipe"]
                )
            }
            heldOutput = duplicate
        }
    }

    func waitUntilExit() {
        condition.lock()
        waitCallCount += 1
        while behavior.isTermIgnoring, !killed {
            condition.wait()
        }
        condition.unlock()
    }

    func sendSignal(_ signal: Int32) {
        condition.lock()
        signals.append(signal)
        if signal == SIGKILL {
            killed = true
            condition.broadcast()
        }
        condition.unlock()
    }

    func releaseHeldPipes() {
        heldOutput?.closeFile()
        heldOutput = nil
    }

    private func write(_ data: Data, to destination: Any?) {
        guard !data.isEmpty, let pipe = destination as? Pipe else { return }
        pipe.fileHandleForWriting.write(data)
    }

    private func duplicateFileHandle(_ fileHandle: FileHandle) -> FileHandle? {
        let descriptor = dup(fileHandle.fileDescriptor)
        guard descriptor >= 0 else { return nil }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

private extension FakeOwnedHelperProcess.Behavior {
    var isTermIgnoring: Bool {
        if case .ignoresTerm = self {
            return true
        }
        return false
    }
}

private func capturedServiceCommandError(_ operation: () throws -> Void) -> ServiceCommandError? {
    do {
        try operation()
        return nil
    } catch let error as ServiceCommandError {
        return error
    } catch {
        return nil
    }
}
