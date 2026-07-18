import Darwin
import Foundation
import Testing
@testable import PTKCore

private struct FakeResolver: ProcessResolving, Sendable {
    let info: PortProcessInfo?
    let error: (any Error)?

    init(info: PortProcessInfo?, error: (any Error)? = nil) {
        self.info = info
        self.error = error
    }

    func info(for port: UInt16) throws -> PortProcessInfo? {
        if let error { throw error }
        return info
    }
}

private final class FakeTerminator: ProcessTerminating, @unchecked Sendable {
    private let lock = NSLock()
    private var storedTerminatedPIDs: [Int] = []
    private var storedFailureMessage: String?

    var terminatedPIDs: [Int] {
        lock.withLock { storedTerminatedPIDs }
    }

    var failureMessage: String? {
        get { lock.withLock { storedFailureMessage } }
        set { lock.withLock { storedFailureMessage = newValue } }
    }

    func terminate(pid: Int) -> String? {
        lock.withLock {
            storedTerminatedPIDs.append(pid)
            return storedFailureMessage
        }
    }
}

private struct FakeConfirmer: KillConfirming {
    let confirmed: Bool

    func confirmKill(target: KillTarget) -> Bool {
        confirmed
    }
}

@Suite struct KillSafetyTests {
    @Test func missingTargetCannotBeKilled() {
        let terminator = FakeTerminator()
        let coordinator = KillCoordinator(
            confirmer: FakeConfirmer(confirmed: true),
            service: KillService(
                resolver: FakeResolver(info: nil),
                terminator: terminator
            )
        )

        #expect(throws: KillError.unsafeTarget) {
            try coordinator.requestKill(target: nil)
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test(arguments: [
        "node 111 me 1u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)",
        "node 111 me 1u IPv6 0x1 0t0 TCP [::1]:3000 (LISTEN)"
    ])
    func exactSingleFamilyIdentityTerminatesOnceAfterConfirmation(
        listenerLine: String
    ) throws {
        let runner = configuredRunner(
            listenerLines: [listenerLine],
            processNames: [111: "node"]
        )
        let terminator = FakeTerminator()
        let coordinator = KillCoordinator(
            confirmer: FakeConfirmer(confirmed: true),
            service: KillService(
                resolver: ProcessLookup(runner: runner),
                terminator: terminator
            )
        )

        let outcome = try coordinator.requestKill(target: target(pid: 111, name: "node"))

        #expect(outcome == .terminated)
        #expect(runner.calls.map(\.0) == ["lsof", "ps"])
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test(arguments: [
        "node 111 me 1u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)",
        "node 111 me 1u IPv6 0x1 0t0 TCP [::1]:3000 (LISTEN)"
    ])
    func confirmationCancelDoesNotRunFreshLookupOrTerminator(
        listenerLine: String
    ) throws {
        let runner = configuredRunner(
            listenerLines: [listenerLine],
            processNames: [111: "node"]
        )
        let terminator = FakeTerminator()
        let coordinator = KillCoordinator(
            confirmer: FakeConfirmer(confirmed: false),
            service: KillService(
                resolver: ProcessLookup(runner: runner),
                terminator: terminator
            )
        )

        let outcome = try coordinator.requestKill(target: target(pid: 111, name: "node"))

        #expect(outcome == .cancelled)
        #expect(runner.calls.isEmpty)
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func samePIDAcrossIPv4AndIPv6TerminatesOnce() throws {
        let runner = configuredRunner(
            listenerLines: [
                "node 111 me 1u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)",
                "node 111 me 2u IPv6 0x2 0t0 TCP [::1]:3000 (LISTEN)"
            ],
            processNames: [111: "node"]
        )
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner),
            terminator: terminator
        )

        try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))

        #expect(terminator.terminatedPIDs == [111])
    }

    @Test(arguments: [
        (
            "node 111 me 1u IPv4 0x1 0t0 TCP localhost:3000 (LISTEN)",
            LsofUntrustedReason.unknownAddress
        ),
        (
            "node 111 me 1u Unknown 0x1 0t0 TCP *:3000 (LISTEN)",
            LsofUntrustedReason.unknownFamily
        ),
        (
            "node 111 me 1u IPv6 0x1 0t0 TCP [::1:3000 (LISTEN)",
            LsofUntrustedReason.malformed
        ),
        (
            "node 111 me 1u IPv4 0x1 0t0 TCP [::1]:3000 (LISTEN)",
            LsofUntrustedReason.familyAddressConflict
        )
    ])
    func untrustedListenerEvidenceBlocksTermination(
        listenerLine: String,
        reason: LsofUntrustedReason
    ) {
        let runner = configuredRunner(
            listenerLines: [listenerLine],
            processNames: [111: "node"]
        )
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner),
            terminator: terminator
        )

        #expect(throws: KillError.untrustedListener(port: 3000, reasons: [reason])) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(runner.calls.map(\.0) == ["lsof"])
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func pidChangeBlocksTermination() {
        let runner = configuredRunner(
            listenerLines: [
                "node 222 me 1u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)"
            ],
            processNames: [222: "node"]
        )
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner),
            terminator: terminator
        )

        #expect(throws: KillError.pidChanged(expected: 111, actual: 222)) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func processNameMismatchBlocksTermination() {
        let runner = configuredRunner(
            listenerLines: [
                "python 111 me 1u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)"
            ],
            processNames: [111: "python"]
        )
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner),
            terminator: terminator
        )

        #expect(throws: KillError.processNameMismatch(expected: "node", actual: "python")) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func vanishedPortBlocksTermination() {
        let runner = configuredRunner(listenerLines: [], processNames: [:])
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner),
            terminator: terminator
        )

        #expect(throws: KillError.portNoLongerListening) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func terminationFailureIsSurfacedAfterOneCall() {
        let terminator = FakeTerminator()
        terminator.failureMessage = "operation not permitted"
        let service = KillService(
            resolver: FakeResolver(
                info: PortProcessInfo(port: 3000, pid: 111, processName: "node")
            ),
            terminator: terminator
        )

        #expect(throws: KillError.terminationFailed("operation not permitted")) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func systemTerminatorSendsExactlyOneSIGTERMAndNeverSIGKILL() {
        let recorder = SignalRecorder()
        let terminator = SystemProcessTerminator { pid, signal in
            recorder.send(pid: pid, signal: signal)
        }

        #expect(terminator.terminate(pid: 111) == nil)
        let calls = recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.pid == pid_t(111))
        #expect(calls.first?.signal == SIGTERM)
        #expect(calls.contains { $0.signal == SIGKILL } == false)
    }

}

private func target(pid: Int, name: String) -> KillTarget {
    KillTarget(port: 3000, pid: pid, processName: name)
}

private func configuredRunner(
    listenerLines: [String],
    processNames: [Int: String]
) -> FakeProcessRunner {
    let runner = FakeProcessRunner()
    let lsofOutput = ([
        "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
    ] + listenerLines).joined(separator: "\n")
    runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
        exitCode: 0,
        stdout: lsofOutput
    )
    for (pid, processName) in processNames {
        runner.results["ps -p \(pid) -o comm="] = ProcessRunResult(
            exitCode: 0,
            stdout: processName
        )
    }
    return runner
}

private enum FailingStage: Sendable, Equatable {
    case lsof
    case ps
}

private struct StageFailingRunner: ProcessRunning, Sendable {
    let stage: FailingStage
    let error: ProcessRunnerError

    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessRunResult {
        if (stage == .lsof && executable == "lsof")
            || (stage == .ps && executable == "ps") {
            throw error
        }
        return ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node 111 me 1u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)
            """
        )
    }
}

private final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [(pid: pid_t, signal: Int32)] = []

    var calls: [(pid: pid_t, signal: Int32)] {
        lock.withLock { recordedCalls }
    }

    func send(pid: pid_t, signal: Int32) -> Int32 {
        lock.withLock {
            recordedCalls.append((pid, signal))
        }
        return 0
    }
}
