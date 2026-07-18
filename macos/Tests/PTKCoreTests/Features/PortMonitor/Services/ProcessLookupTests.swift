import Testing
import Foundation
@testable import PTKCore

@Suite struct ProcessLookupTests {
    @Test func infoRunsOneLsofThenResolvesVerifiedIdentity() throws {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
            """
        )
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(
            exitCode: 0,
            stdout: " node \n"
        )

        let info = try ProcessLookup(runner: runner).info(for: 3000)

        #expect(info?.pid == 111)
        #expect(info?.processName == "node")
        #expect(runner.calls.map(\.0) == ["lsof", "ps"])
    }

    @Test func infoRejectsAmbiguousListenersForPortWithSortedPIDs() {
        let snapshot = LsofParser().parse(
            """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            vite    222 me   1u IPv6 0x2    0t0      TCP [::1]:3000 (LISTEN)
            node    111 me   1u IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
            """
        )

        #expect(throws: ProcessLookupError.ambiguousListeners(port: 3000, pids: [111, 222])) {
            try ProcessLookup(runner: FakeProcessRunner()).info(for: 3000, using: snapshot)
        }
    }

    @Test func infoRejectsUntrustedListenersWithStableReasons() {
        let snapshot = LsofParser().parse(
            """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP localhost:3000 (LISTEN)
            """
        )

        #expect(
            throws: ProcessLookupError.untrustedListeners(
                port: 3000,
                reasons: [.unknownAddress]
            )
        ) {
            try ProcessLookup(runner: FakeProcessRunner()).info(for: 3000, using: snapshot)
        }
    }

    @Test func infoReturnsNilForAbsentPortWithoutRunningPS() throws {
        let runner = FakeProcessRunner()
        let snapshot = LsofParser().parse(
            "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
        )

        #expect(try ProcessLookup(runner: runner).info(for: 3000, using: snapshot) == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func processNameTrimsWhitespace() throws {
        let runner = FakeProcessRunner()
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(
            exitCode: 0,
            stdout: " /usr/local/bin/node \n"
        )

        #expect(try ProcessLookup(runner: runner).processName(pid: 111) == "/usr/local/bin/node")
    }

    @Test func processNameTreatsInvalidPIDAsMissingWithoutRunningPS() throws {
        let runner = FakeProcessRunner()

        #expect(try ProcessLookup(runner: runner).processName(pid: 0) == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func lsofUsesPinnedTwoSecondTimeout() throws {
        let runner = TimeoutRecordingProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: ""
        )

        _ = try ProcessLookup(runner: runner).listeningSnapshot()

        #expect(runner.calls == [
            TimeoutProcessCall(
                executable: "lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"],
                timeout: 2
            )
        ])
    }

    @Test func psUsesPinnedOneSecondTimeout() throws {
        let runner = TimeoutRecordingProcessRunner()
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: "node")

        _ = try ProcessLookup(runner: runner).processName(pid: 111)

        #expect(runner.calls == [
            TimeoutProcessCall(
                executable: "ps",
                arguments: ["-p", "111", "-o", "comm="],
                timeout: 1
            )
        ])
    }

    @Test(arguments: [
        ProcessRunnerError.launchFailed("not found"),
        ProcessRunnerError.timedOut,
        ProcessRunnerError.outputLimitExceeded(streams: [.stdout, .stderr]),
        ProcessRunnerError.pipeDrainTimedOut
    ])
    func psMapsOwnedHelperFailuresToProcessNameFailure(error: ProcessRunnerError) {
        let runner = TimeoutRecordingProcessRunner()
        runner.error = error

        #expect(throws: ProcessLookupError.processNameFailed(pid: 111, message: error.description)) {
            try ProcessLookup(runner: runner).processName(pid: 111)
        }
        #expect(runner.calls.map(\.timeout) == [1])
    }

    @Test(arguments: [
        ProcessRunnerError.launchFailed("not found"),
        ProcessRunnerError.timedOut,
        ProcessRunnerError.outputLimitExceeded(streams: [.stdout, .stderr]),
        ProcessRunnerError.pipeDrainTimedOut
    ])
    func lsofMapsOwnedHelperFailuresToLookupFailure(error: ProcessRunnerError) {
        let runner = TimeoutRecordingProcessRunner()
        runner.error = error

        #expect(throws: ProcessLookupError.lsofFailed(error.description)) {
            try ProcessLookup(runner: runner).listeningSnapshot()
        }
        #expect(runner.calls.map(\.timeout) == [2])
    }

}

private struct TimeoutProcessCall: Equatable {
    let executable: String
    let arguments: [String]
    let timeout: TimeInterval
}

private final class TimeoutRecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: ProcessRunResult] = [:]
    private var storedError: ProcessRunnerError?
    private var storedCalls: [TimeoutProcessCall] = []

    var results: [String: ProcessRunResult] {
        get { lock.withLock { storedResults } }
        set { lock.withLock { storedResults = newValue } }
    }

    var error: ProcessRunnerError? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    var calls: [TimeoutProcessCall] {
        lock.withLock { storedCalls }
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        try lock.withLock {
            storedCalls.append(
                TimeoutProcessCall(
                    executable: executable,
                    arguments: arguments,
                    timeout: timeout
                )
            )
            if let storedError { throw storedError }
            let key = ([executable] + arguments).joined(separator: " ")
            return storedResults[key] ?? ProcessRunResult(
                exitCode: 1,
                stdout: "",
                stderr: "missing fake result"
            )
        }
    }
}
