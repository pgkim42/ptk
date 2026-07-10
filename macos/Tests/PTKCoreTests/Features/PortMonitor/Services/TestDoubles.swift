import Foundation

@testable import PTKCore

final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: ProcessRunResult] = [:]
    private var storedCalls: [(String, [String])] = []

    var results: [String: ProcessRunResult] {
        get { lock.withLock { storedResults } }
        set { lock.withLock { storedResults = newValue } }
    }

    var calls: [(String, [String])] {
        lock.withLock { storedCalls }
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        lock.withLock {
            storedCalls.append((executable, arguments))
            let key = ([executable] + arguments).joined(separator: " ")
            return storedResults[key] ?? ProcessRunResult(
                exitCode: 1,
                stdout: "",
                stderr: "missing fake result"
            )
        }
    }
}

struct FakeSocketConnector: SocketConnecting, Sendable {
    let openPorts: Set<UInt16>

    func isListening(host: String, port: UInt16, timeout: Double) -> Bool {
        openPorts.contains(port)
    }
}
