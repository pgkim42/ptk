import Foundation
import Testing
@testable import PTKCore

@Suite struct PortScannerTests {
    @Test func scansConfiguredPortsWithFakeConnectorAndLookup() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
"""
        )
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: "node\n")

        let scanner = PortScanner(
            connector: FakeSocketConnector(openPorts: [3000]),
            lookup: ProcessLookup(runner: runner)
        )

        let statuses = scanner.scan(ports: [3000, 3001])
        #expect(statuses == [
            PortStatus(port: 3000, isOpen: true, pid: 111, processName: "node"),
            PortStatus(port: 3001, isOpen: false)
        ])
    }

    @Test func lookupFailureKeepsOpenPortWithoutFailingScan() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(exitCode: 1, stdout: "", stderr: "denied")
        let scanner = PortScanner(
            connector: FakeSocketConnector(openPorts: [5173]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [5173])[0]
        #expect(status.port == 5173)
        #expect(status.isOpen)
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.message?.contains("process lookup failed") == true)
    }

    @Test func processNameFailureKeepsOpenPortWithoutIdentityAndDisablesKillTarget() {
        let runner = ProcessNameFailingRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
            """
        )
        let scanner = PortScanner(
            connector: FakeSocketConnector(openPorts: [3000]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]
        let row = MenuModel(statuses: [status]).rows[0]

        #expect(status.isOpen)
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(
            status.message
                == "process lookup failed: process name lookup failed for PID 111: process timed out"
        )
        #expect(
            row.killUnavailableCause
                == .lookupFailed(
                    message: "process lookup failed: process name lookup failed for PID 111: process timed out"
                )
        )
        #expect(row.killTarget == nil)
        #expect(!row.canRequestKill)
    }

    @Test func ambiguousSamePortListenersDisableKillTarget() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
            vite    222 me   1u IPv6 0x2    0t0      TCP *:3000 (LISTEN)
            """
        )
        let scanner = PortScanner(
            connector: FakeSocketConnector(openPorts: [3000]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]
        let row = MenuModel(statuses: [status]).rows[0]
        #expect(status.isOpen)
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.message?.contains("ambiguous") == true)
        #expect(row.killTarget == nil)
        #expect(!row.canRequestKill)
    }
}

private final class ProcessNameFailingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: ProcessRunResult] = [:]

    var results: [String: ProcessRunResult] {
        get { lock.withLock { storedResults } }
        set { lock.withLock { storedResults = newValue } }
    }

    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessRunResult {
        if executable == "ps" {
            throw ProcessRunnerError.timedOut
        }
        let key = ([executable] + arguments).joined(separator: " ")
        return lock.withLock {
            storedResults[key] ?? ProcessRunResult(
                exitCode: 1,
                stdout: "",
                stderr: "missing fake result"
            )
        }
    }
}
