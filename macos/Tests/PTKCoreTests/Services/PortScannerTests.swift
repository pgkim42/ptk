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
}
