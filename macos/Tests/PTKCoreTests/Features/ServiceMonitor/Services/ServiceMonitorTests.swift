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
