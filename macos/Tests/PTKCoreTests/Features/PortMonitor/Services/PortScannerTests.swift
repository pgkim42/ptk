import Foundation
import Testing
@testable import PTKCore

@Suite struct PortScannerTests {
    @Test func ipv4OnlyListenerIsOpen() {
        let connector = RecordingSocketConnector(openHostsByPort: [3000: ["127.0.0.1"]])

        #expect(connector.isListeningOnLocalhost(port: 3000, timeout: 1))
        #expect(connector.calls.map(\.host) == ["127.0.0.1"])
    }

    @Test func ipv6OnlyListenerIsOpen() {
        let connector = RecordingSocketConnector(openHostsByPort: [3000: ["::1"]])

        #expect(connector.isListeningOnLocalhost(port: 3000, timeout: 1))
        #expect(connector.calls.map(\.host) == ["127.0.0.1", "::1"])
    }

    @Test func dualStackListenerStopsAfterIPv4Success() {
        let connector = RecordingSocketConnector(
            openHostsByPort: [3000: ["127.0.0.1", "::1"]]
        )

        #expect(connector.isListeningOnLocalhost(port: 3000, timeout: 1))
        #expect(connector.calls.map(\.host) == ["127.0.0.1"])
    }

    @Test func bothClosedFamiliesAreClosed() {
        let connector = RecordingSocketConnector()

        #expect(!connector.isListeningOnLocalhost(port: 3000, timeout: 1))
        #expect(connector.calls.map(\.host) == ["127.0.0.1", "::1"])
    }

    @Test func earlyIPv4SuccessDoesNotSpendRemainingBudget() {
        let clock = ManualProbeClock()
        let connector = RecordingSocketConnector(
            openHostsByPort: [3000: ["127.0.0.1"]],
            elapsedByHost: ["127.0.0.1": 0.125],
            clock: clock
        )

        let isOpen = connector.isListeningOnLocalhost(
            port: 3000,
            timeout: 1,
            now: { clock.now }
        )
        #expect(isOpen)
        #expect(connector.calls == [
            SocketProbeCall(host: "127.0.0.1", port: 3000, timeout: 0.5)
        ])
        #expect(clock.now == 0.125)
    }

    @Test func ipv6ReceivesOnlyBudgetRemainingAfterIPv4() {
        let clock = ManualProbeClock()
        let connector = RecordingSocketConnector(
            openHostsByPort: [3000: ["::1"]],
            elapsedByHost: ["127.0.0.1": 0.125, "::1": 0.25],
            clock: clock
        )

        let isOpen = connector.isListeningOnLocalhost(
            port: 3000,
            timeout: 1,
            now: { clock.now }
        )
        #expect(isOpen)
        #expect(connector.calls == [
            SocketProbeCall(host: "127.0.0.1", port: 3000, timeout: 0.5),
            SocketProbeCall(host: "::1", port: 3000, timeout: 0.875)
        ])
        #expect(clock.now == 0.375)
    }

    @Test func ipv4ExhaustionLeavesOnlyHalfBudgetForIPv6() {
        let clock = ManualProbeClock()
        let connector = RecordingSocketConnector(
            openHostsByPort: [3000: ["::1"]],
            elapsedByHost: ["127.0.0.1": 1, "::1": 1],
            clock: clock
        )

        let isOpen = connector.isListeningOnLocalhost(
            port: 3000,
            timeout: 1,
            now: { clock.now }
        )
        #expect(!isOpen)
        #expect(connector.calls == [
            SocketProbeCall(host: "127.0.0.1", port: 3000, timeout: 0.5),
            SocketProbeCall(host: "::1", port: 3000, timeout: 0.5)
        ])
        #expect(clock.now == 1)
    }

    @Test func scanUsesOneSnapshotAndMapsVerifiedIdentity() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
            vite    222 me   1u IPv6 0x2    0t0      TCP [::1]:3001 (LISTEN)
            """
        )
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: "node\n")
        runner.results["ps -p 222 -o comm="] = ProcessRunResult(exitCode: 0, stdout: "vite\n")
        let connector = RecordingSocketConnector(
            openHostsByPort: [3000: ["127.0.0.1"], 3001: ["::1"]]
        )
        let scanner = PortScanner(
            connector: connector,
            lookup: ProcessLookup(runner: runner),
            timeout: 1
        )

        let statuses = scanner.scan(ports: [3000, 3001])

        #expect(statuses == [
            PortStatus(
                port: 3000,
                isOpen: true,
                identityState: .verified(
                    VerifiedProcessIdentity(pid: 111, processName: "node")!
                )
            ),
            PortStatus(
                port: 3001,
                isOpen: true,
                identityState: .verified(
                    VerifiedProcessIdentity(pid: 222, processName: "vite")!
                )
            )
        ])
        #expect(runner.calls.filter { $0.0 == "lsof" }.count == 1)
        #expect(connector.calls.map(\.host) == ["127.0.0.1", "127.0.0.1", "::1"])
    }

    @Test func closedSocketStaysClosedDespiteVerifiedListenerEvidence() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
            """
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]

        #expect(status == PortStatus(port: 3000, isOpen: false, identityState: nil))
        #expect(runner.calls.filter { $0.0 == "lsof" }.count == 1)
        #expect(runner.calls.contains { $0.0 == "ps" } == false)
    }

    @Test func absentListenerEvidenceMapsToNoVerifiedListener() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: ""
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(openHostsByPort: [3000: ["127.0.0.1"]]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]

        #expect(status.isOpen)
        #expect(status.identityState == .unavailable(.noVerifiedListener))
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.killTarget == nil)
    }

    @Test func remoteListenerEvidenceIsUntrustedWithoutIdentity() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP 192.168.1.10:3000 (LISTEN)
            """
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(openHostsByPort: [3000: ["127.0.0.1"]]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]

        #expect(status.isOpen)
        #expect(
            status.identityState
                == .unavailable(.untrustedListener(
                    message: "untrusted listeners for port 3000: remoteOrInterfaceOnly"
                ))
        )
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.killTarget == nil)
        #expect(runner.calls.contains { $0.0 == "ps" } == false)
    }

    @Test func ambiguousListenersMapSortedPIDsWithoutIdentity() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            vite    222 me   1u IPv6 0x2    0t0      TCP [::1]:3000 (LISTEN)
            node    111 me   1u IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
            """
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(openHostsByPort: [3000: ["::1"]]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]

        #expect(status.isOpen)
        #expect(status.identityState == .unavailable(.ambiguousListeners(pids: [111, 222])))
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.killTarget == nil)
    }

    @Test func processNameUnavailableDoesNotAttachPartialIdentity() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
            """
        )
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(
            exitCode: 1,
            stdout: "",
            stderr: "gone"
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(openHostsByPort: [3000: ["127.0.0.1"]]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]

        #expect(status.isOpen)
        #expect(status.identityState == .unavailable(.processNameUnavailable(pid: 111)))
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.killTarget == nil)
    }

    @Test func lookupFailureKeepsSocketOpenWithoutIdentity() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 1,
            stdout: "",
            stderr: "denied"
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(openHostsByPort: [5173: ["::1"]]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [5173])[0]

        #expect(status.isOpen)
        #expect(status.identityState == .unavailable(.lookupFailed(message: "denied")))
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.killTarget == nil)
    }

    @Test func processNameLookupFailureMapsLookupFailureWithoutIdentity() {
        let runner = ProcessNameFailingRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
            """
        )
        let scanner = PortScanner(
            connector: RecordingSocketConnector(openHostsByPort: [3000: ["127.0.0.1"]]),
            lookup: ProcessLookup(runner: runner)
        )

        let status = scanner.scan(ports: [3000])[0]

        #expect(status.isOpen)
        #expect(
            status.identityState
                == .unavailable(.lookupFailed(
                    message: "process name lookup failed for PID 111: process timed out"
                ))
        )
        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(status.killTarget == nil)
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

private struct SocketProbeCall: Equatable {
    let host: String
    let port: UInt16
    let timeout: TimeInterval
}

private final class ManualProbeClock: @unchecked Sendable {
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

private final class RecordingSocketConnector: SocketConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private let openHostsByPort: [UInt16: Set<String>]
    private let elapsedByHost: [String: TimeInterval]
    private let clock: ManualProbeClock?
    private var storedCalls: [SocketProbeCall] = []

    init(
        openHostsByPort: [UInt16: Set<String>] = [:],
        elapsedByHost: [String: TimeInterval] = [:],
        clock: ManualProbeClock? = nil
    ) {
        self.openHostsByPort = openHostsByPort
        self.elapsedByHost = elapsedByHost
        self.clock = clock
    }

    var calls: [SocketProbeCall] {
        lock.withLock { storedCalls }
    }

    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        lock.withLock {
            storedCalls.append(SocketProbeCall(host: host, port: port, timeout: timeout))
        }

        let elapsed = elapsedByHost[host] ?? 0
        clock?.advance(by: min(elapsed, max(timeout, 0)))
        return openHostsByPort[port]?.contains(host) == true && elapsed <= timeout
    }
}
