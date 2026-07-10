import Testing
import Foundation
@testable import PTKCore

@Suite struct ProcessLookupTests {
    @Test func mapsLsofOutputToPIDSetMap() throws {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
"""
        )

        let lookup = ProcessLookup(runner: runner)
        #expect(try lookup.listeningPortPIDMap() == [3000: Set([111])])
    }

    @Test func infoRejectsAmbiguousListenersForPort() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
            vite    222 me   1u IPv4 0x2    0t0      TCP *:3000 (LISTEN)
            """
        )

        let lookup = ProcessLookup(runner: runner)
        #expect(throws: ProcessLookupError.ambiguousListeners(port: 3000, pids: [111, 222])) {
            try lookup.info(for: 3000)
        }
    }

    @Test func processNameTrimsWhitespace() throws {
        let runner = FakeProcessRunner()
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: " /usr/local/bin/node \n")

        let lookup = ProcessLookup(runner: runner)
        #expect(try lookup.processName(pid: 111) == "/usr/local/bin/node")
    }

    @Test func processNameTreatsEmptySuccessfulOutputAsMissing() throws {
        let runner = FakeProcessRunner()
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: " \n")

        #expect(try ProcessLookup(runner: runner).processName(pid: 111) == nil)
    }

    @Test func processNameTreatsOrdinaryNonzeroExitAsMissing() throws {
        let runner = FakeProcessRunner()
        runner.results["ps -p 222 -o comm="] = ProcessRunResult(
            exitCode: 1,
            stdout: "",
            stderr: "missing"
        )

        #expect(try ProcessLookup(runner: runner).processName(pid: 222) == nil)
    }

    @Test func processNameTreatsInvalidPIDAsMissingWithoutRunningPS() throws {
        let runner = FakeProcessRunner()

        #expect(try ProcessLookup(runner: runner).processName(pid: 0) == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func lsofFailureIsSurfaced() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(exitCode: 1, stdout: "", stderr: "denied")

        let lookup = ProcessLookup(runner: runner)
        #expect(throws: ProcessLookupError.lsofFailed("denied")) {
            try lookup.listeningPortPIDMap()
        }
    }

    @Test func lsofUsesPinnedTwoSecondTimeout() throws {
        let runner = TimeoutRecordingProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(exitCode: 0, stdout: "")

        _ = try ProcessLookup(runner: runner).listeningPortPIDMap()

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
            try ProcessLookup(runner: runner).listeningPortPIDMap()
        }
    }
}

private struct TimeoutProcessCall: Equatable {
    let executable: String
    let arguments: [String]
    let timeout: TimeInterval
}

private final class TimeoutRecordingProcessRunner: ProcessRunning {
    var results: [String: ProcessRunResult] = [:]
    var error: ProcessRunnerError?
    var calls: [TimeoutProcessCall] = []

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        calls.append(TimeoutProcessCall(executable: executable, arguments: arguments, timeout: timeout))
        return try result(executable, arguments: arguments)
    }

    private func result(_ executable: String, arguments: [String]) throws -> ProcessRunResult {
        if let error { throw error }
        let key = ([executable] + arguments).joined(separator: " ")
        return results[key] ?? ProcessRunResult(exitCode: 1, stdout: "", stderr: "missing fake result")
    }
}
