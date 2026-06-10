import Foundation
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

    @Test func dockerPsFailureDoesNotPolluteDockerDaemonStatus() {
        let runner = FakeServiceCommandRunner(results: [
            "docker info": ServiceCommandResult(exitCode: 0, stdout: "Server Version: 27.0.0\n"),
            "docker ps --format {{.Names}}\t{{.Ports}}": ServiceCommandResult(exitCode: 1, stdout: "", stderr: "boom")
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

    @Test func systemServiceCommandRunnerReturnsPromptlyAfterTimeout() {
        let runner = SystemServiceCommandRunner()
        let startedAt = Date()

        #expect(throws: ServiceCommandError.timedOut) {
            try runner.run(
                "sh",
                arguments: ["-c", "trap '' TERM; sleep 5"],
                timeout: 0.1,
                environmentPath: "/bin:/usr/bin"
            )
        }
        #expect(Date().timeIntervalSince(startedAt) < 1)
    }

    @Test func systemServiceCommandRunnerReapsTimedOutProcess() {
        let process = FakeServiceProcess()
        let runner = SystemServiceCommandRunner(processFactory: { process })

        #expect(throws: ServiceCommandError.timedOut) {
            try runner.run(
                "docker",
                arguments: ["info"],
                timeout: 0.1,
                environmentPath: "/bin:/usr/bin"
            )
        }

        #expect(process.didTerminate)
        let deadline = Date().addingTimeInterval(0.5)
        while process.waitUntilExitCallCount < 2 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(process.waitUntilExitCallCount == 2)
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
}

private final class FakeServiceCommandRunner: ServiceCommandRunning, @unchecked Sendable {
    var results: [String: ServiceCommandResult]
    var error: Error?
    var calls: [ServiceCommandCall] = []

    init(results: [String: ServiceCommandResult] = [:], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environmentPath: String) throws -> ServiceCommandResult {
        calls.append(ServiceCommandCall(executable: executable, arguments: arguments, timeout: timeout, environmentPath: environmentPath))
        if let error { throw error }
        return results[([executable] + arguments).joined(separator: " ")] ?? ServiceCommandResult(exitCode: 1, stdout: "", stderr: "missing fake result")
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

private final class FakeServiceProcess: ServiceProcess, @unchecked Sendable {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    var terminationStatus: Int32 = 0
    var didTerminate = false
    var waitUntilExitCallCount = 0

    func run() throws {}

    func waitUntilExit() {
        waitUntilExitCallCount += 1
        if !didTerminate {
            Thread.sleep(forTimeInterval: 1)
        }
    }

    func terminate() {
        didTerminate = true
    }
}
