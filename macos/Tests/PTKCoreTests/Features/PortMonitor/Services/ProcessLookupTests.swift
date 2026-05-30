import Testing
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

    @Test func processNameTrimsWhitespace() {
        let runner = FakeProcessRunner()
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: " /usr/local/bin/node \n")

        let lookup = ProcessLookup(runner: runner)
        #expect(lookup.processName(pid: 111) == "/usr/local/bin/node")
    }

    @Test func processNameTreatsEmptyOrFailedOutputAsMissing() {
        let runner = FakeProcessRunner()
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: " \n")
        runner.results["ps -p 222 -o comm="] = ProcessRunResult(exitCode: 1, stdout: "", stderr: "missing")

        let lookup = ProcessLookup(runner: runner)
        #expect(lookup.processName(pid: 111) == nil)
        #expect(lookup.processName(pid: 222) == nil)
    }

    @Test func lsofFailureIsSurfaced() {
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(exitCode: 1, stdout: "", stderr: "denied")

        let lookup = ProcessLookup(runner: runner)
        #expect(throws: ProcessLookupError.lsofFailed("denied")) {
            try lookup.listeningPortPIDMap()
        }
    }
}
