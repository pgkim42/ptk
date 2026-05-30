@testable import PTKCore

final class FakeProcessRunner: ProcessRunning {
    var results: [String: ProcessRunResult] = [:]
    var calls: [(String, [String])] = []

    func run(_ executable: String, arguments: [String]) throws -> ProcessRunResult {
        calls.append((executable, arguments))
        let key = ([executable] + arguments).joined(separator: " ")
        return results[key] ?? ProcessRunResult(exitCode: 1, stdout: "", stderr: "missing fake result")
    }
}

struct FakeSocketConnector: SocketConnecting {
    let openPorts: Set<UInt16>

    func isListening(host: String, port: UInt16, timeout: Double) -> Bool {
        openPorts.contains(port)
    }
}
