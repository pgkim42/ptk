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
    @Test func waitsForPortReleaseWithoutResendingSignal() async throws {
        let info = PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
        let resolver = ScriptedResolver([.success(info), .success(info), .success(nil)])
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: resolver, terminator: terminator,
            connector: FakeSocketConnector(openPorts: [])
        )
        try await service.terminateAndWaitForPortRelease(
            target: target(pid: 111, name: "node"), pollInterval: 0.01
        )
        #expect(resolver.calls == 3)
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func signalAcceptedButListenerRemainsIsNotSuccess() async {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(info: PortProcessInfo(
                port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime
            )),
            terminator: terminator
        )
        await #expect(throws: KillError.portStillListening(port: 3000)) {
            try await service.terminateAndWaitForPortRelease(target: target(pid: 111, name: "node"), timeout: 0)
        }
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func replacementOnSamePortIsNotTerminated() async {
        let old = PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
        let new = PortProcessInfo(
            port: 3000, pid: 111, processName: "node",
            startTime: ProcessStartTime(seconds: 2, microseconds: 0)
        )
        let terminator = FakeTerminator()
        let service = KillService(resolver: ScriptedResolver([.success(old), .success(new)]), terminator: terminator)
        await #expect(throws: KillError.portReoccupied(port: 3000, pid: 111)) {
            try await service.terminateAndWaitForPortRelease(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func postSignalLookupFailureIsUnconfirmed() async {
        let info = PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ScriptedResolver([.success(info), .failure(.lsofFailed("denied"))]),
            terminator: terminator
        )
        await #expect(throws: KillError.terminationUnconfirmed("denied")) {
            try await service.terminateAndWaitForPortRelease(target: target(pid: 111, name: "node"), timeout: 0)
        }
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func missingListenerMetadataWithRespondingSocketIsUnconfirmed() async {
        let info = PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
        let service = KillService(
            resolver: ScriptedResolver([.success(info), .success(nil)]),
            terminator: FakeTerminator(), connector: FakeSocketConnector(openPorts: [3000])
        )
        await #expect(throws: KillError.terminationUnconfirmed("포트 3000가 응답하지만 수신 프로세스를 확인할 수 없습니다.")) {
            try await service.terminateAndWaitForPortRelease(target: target(pid: 111, name: "node"), timeout: 0)
        }
    }

    @Test func transientObservationFailureCanRecoverWithoutAnotherSignal() async throws {
        let info = PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ScriptedResolver([.success(info), .failure(.lsofFailed("timeout")), .success(nil)]),
            terminator: terminator, connector: FakeSocketConnector(openPorts: [])
        )
        try await service.terminateAndWaitForPortRelease(target: target(pid: 111, name: "node"), pollInterval: 0.01)
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test func cancellationDuringObservationStopsWithoutAnotherSignal() async throws {
        let info = PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
        let resolver = ScriptedResolver([.success(info)])
        let terminator = FakeTerminator()
        let service = KillService(resolver: resolver, terminator: terminator)
        let task = Task {
            try await service.terminateAndWaitForPortRelease(target: target(pid: 111, name: "node"), pollInterval: 1)
        }
        defer { task.cancel() }
        for _ in 0..<100 where resolver.calls < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(resolver.calls == 2)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(terminator.terminatedPIDs == [111])
    }

    @Test(arguments: [
        ProcessLookupError.processStartTimeUnavailable(pid: 111),
        ProcessLookupError.processChangedDuringLookup(pid: 111)
    ])
    func uncertainStartTimeBlocksTermination(error: ProcessLookupError) {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(info: nil, error: error),
            terminator: terminator
        )
        #expect(throws: KillError.resolverFailed(error.description)) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func reusedPIDWithSameNameBlocksTermination() {
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: FakeResolver(info: PortProcessInfo(
                port: 3000, pid: 111, processName: "node",
                startTime: ProcessStartTime(seconds: 1, microseconds: 1)
            )),
            terminator: terminator
        )

        #expect(throws: KillError.processRestarted(pid: 111)) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

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
                resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
                terminator: terminator
            )
        )

        let outcome = try coordinator.requestKill(target: target(pid: 111, name: "node"))

        #expect(outcome == .signalSent)
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
                resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
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
            resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
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
            resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
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
            resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
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
            resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
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
            resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
            terminator: terminator
        )

        #expect(throws: KillError.portNoLongerListening) {
            try service.terminateAfterRevalidation(target: target(pid: 111, name: "node"))
        }
        #expect(terminator.terminatedPIDs.isEmpty)
    }

    @Test func lastVanishedListenerWithEmptyLsofResultUsesNoLongerListeningError() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 1,
            stdout: "",
            stderr: ""
        )
        let terminator = FakeTerminator()
        let service = KillService(
            resolver: ProcessLookup(runner: runner, startTime: { _ in fixtureStartTime }),
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
                info: PortProcessInfo(port: 3000, pid: 111, processName: "node", startTime: fixtureStartTime)
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

private final class ScriptedResolver: ProcessResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<PortProcessInfo?, ProcessLookupError>]
    private var count = 0

    init(_ responses: [Result<PortProcessInfo?, ProcessLookupError>]) {
        self.responses = responses
    }

    var calls: Int { lock.withLock { count } }

    func info(for port: UInt16) throws -> PortProcessInfo? {
        try lock.withLock {
            count += 1
            let response = responses.count > 1 ? responses.removeFirst() : responses[0]
            return try response.get()
        }
    }
}

private func target(pid: Int, name: String) -> KillTarget {
    KillTarget(port: 3000, pid: pid, processName: name, startTime: fixtureStartTime)
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

private let fixtureStartTime = ProcessStartTime(seconds: 1, microseconds: 0)
