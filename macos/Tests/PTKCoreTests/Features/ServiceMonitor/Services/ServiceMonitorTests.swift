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
