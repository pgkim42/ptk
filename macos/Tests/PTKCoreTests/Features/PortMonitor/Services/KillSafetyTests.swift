import Darwin
import Foundation
import Testing
@testable import PTKCore

struct FakeResolver: ProcessResolving, Sendable {
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

final class FakeTerminator: ProcessTerminating, @unchecked Sendable {
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

struct FakeConfirmer: KillConfirming {
    let confirmed: Bool

    func confirmKill(target: KillTarget) -> Bool {
        confirmed
    }
}

@Suite struct KillSafetyTests {
    @Test func missingUnsafeTargetCannotBeKilled() {
        let coordinator = KillCoordinator(
            confirmer: FakeConfirmer(confirmed: true),
            service: KillService(resolver: FakeResolver(info: nil), terminator: FakeTerminator())
        )

        #expect(KillTarget.safe(port: 3000, pid: nil, processName: "node") == nil)
        #expect(KillTarget.safe(port: 3000, pid: Optional(0), processName: "node") == nil)
        #expect(KillTarget.safe(port: 3000, pid: 111, processName: nil) == nil)
        #expect(throws: KillError.unsafeTarget) {
            try coordinator.requestKill(target: nil)
        }
    }

    @Test func confirmationCancelDoesNotCallTerminator() throws {
        let terminator = FakeTerminator()
        let coordinator = KillCoordinator(
            confirmer: FakeConfirmer(confirmed: false),
            service: KillService(
                resolver: FakeResolver(info: PortProcessInfo(port: 3000, pid: 111, processName: "node")),
                terminator: terminator
            )
        )

        let outcome = try coordinator.requestKill(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        #expect(outcome == .cancelled)
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func matchingRevalidationAllowsSoftTerminate() throws {
        let terminator = FakeTerminator()
        let coordinator = KillCoordinator(
            confirmer: FakeConfirmer(confirmed: true),
            service: KillService(
                resolver: FakeResolver(info: PortProcessInfo(port: 3000, pid: 111, processName: "node")),
                terminator: terminator
            )
        )

        let outcome = try coordinator.requestKill(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        #expect(outcome == .terminated)
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func systemTerminatorSendsExactlyOneSIGTERM() {
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

    @Test func pidChangeBlocksTermination() {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(info: PortProcessInfo(port: 3000, pid: 222, processName: "node")),
            terminator: terminator
        )

        #expect(throws: KillError.pidChanged(expected: 111, actual: 222)) {
            try service.terminateAfterRevalidation(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test(arguments: [Optional<String>.none, Optional<String>("")])
    func unavailableFreshProcessNameBlocksTermination(processName: String?) {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(
                info: PortProcessInfo(port: 3000, pid: 111, processName: processName)
            ),
            terminator: terminator
        )

        #expect(throws: KillError.processNameUnavailable) {
            try service.terminateAfterRevalidation(
                target: KillTarget(port: 3000, pid: 111, processName: "node")
            )
        }
        #expect(terminator.terminatedPIDs == [])
    }

    @Test func processNameMismatchBlocksTermination() {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(info: PortProcessInfo(port: 3000, pid: 111, processName: "python")),
            terminator: terminator
        )

        #expect(throws: KillError.processNameMismatch(expected: "node", actual: "python")) {
            try service.terminateAfterRevalidation(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func vanishedPortBlocksTermination() {
        let terminator = FakeTerminator()
        let service = KillService(resolver: FakeResolver(info: nil), terminator: terminator)

        #expect(throws: KillError.portNoLongerListening) {
            try service.terminateAfterRevalidation(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }


    @Test func resolverErrorIsSurfaced() {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(info: nil, error: ProcessLookupError.lsofFailed("denied")),
            terminator: terminator
        )

        #expect(throws: KillError.resolverFailed("denied")) {
            try service.terminateAfterRevalidation(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test(arguments: [
        (
            ProcessRunnerError.launchFailed("not found"),
            "process name lookup failed for PID 111: not found"
        ),
        (
            ProcessRunnerError.timedOut,
            "process name lookup failed for PID 111: process timed out"
        ),
        (
            ProcessRunnerError.outputLimitExceeded(streams: [.stdout, .stderr]),
            "process name lookup failed for PID 111: process output limit exceeded: stderr, stdout"
        ),
        (
            ProcessRunnerError.pipeDrainTimedOut,
            "process name lookup failed for PID 111: process output pipes did not close after exit"
        )
    ])
    func processNameRunnerFailureBecomesResolverFailureWithoutTermination(
        error: ProcessRunnerError,
        expectedMessage: String
    ) {
        let runner = RevalidationProcessNameFailingRunner(error: error)
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner),
            terminator: terminator
        )

        #expect(throws: KillError.resolverFailed(expectedMessage)) {
            try service.terminateAfterRevalidation(
                target: KillTarget(port: 3000, pid: 111, processName: "node")
            )
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func terminationFailureIsSurfaced() {
        let terminator = FakeTerminator()
        terminator.failureMessage = "operation not permitted"
        let service = KillService(
            resolver: FakeResolver(info: PortProcessInfo(port: 3000, pid: 111, processName: "node")),
            terminator: terminator
        )

        #expect(throws: KillError.terminationFailed("operation not permitted")) {
            try service.terminateAfterRevalidation(target: KillTarget(port: 3000, pid: 111, processName: "node"))
        }
    }
}

private struct RevalidationProcessNameFailingRunner: ProcessRunning, Sendable {
    let error: ProcessRunnerError

    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessRunResult {
        if executable == "ps" {
            throw error
        }
        return ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
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
