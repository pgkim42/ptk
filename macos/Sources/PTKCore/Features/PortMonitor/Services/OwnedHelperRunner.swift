import Darwin
import Dispatch
import Foundation

public enum OwnedHelperStream: String, Hashable, Sendable {
    case stdout
    case stderr
}

public struct OwnedHelperConfiguration: Equatable, Sendable {
    public static let defaultOutputLimit = 4 * 1_024 * 1_024

    public let timeout: TimeInterval
    public let outputLimit: Int
    public let terminationGrace: TimeInterval
    public let postExitDrainGrace: TimeInterval

    public init(
        timeout: TimeInterval,
        outputLimit: Int = OwnedHelperConfiguration.defaultOutputLimit,
        terminationGrace: TimeInterval = 0.25,
        postExitDrainGrace: TimeInterval = 0.25
    ) {
        self.timeout = timeout
        self.outputLimit = outputLimit
        self.terminationGrace = terminationGrace
        self.postExitDrainGrace = postExitDrainGrace
    }
}

public enum OwnedHelperError: Error, Equatable, CustomStringConvertible, Sendable {
    case launchFailed(String)
    case timedOut
    case outputLimitExceeded(streams: Set<OwnedHelperStream>)
    case pipeDrainTimedOut

    public var description: String {
        switch self {
        case .launchFailed(let message):
            return message
        case .timedOut:
            return "helper process timed out"
        case .outputLimitExceeded(let streams):
            let names = streams.map(\.rawValue).sorted().joined(separator: ", ")
            return "helper process output limit exceeded: \(names)"
        case .pipeDrainTimedOut:
            return "helper process output pipes did not close after exit"
        }
    }
}

public struct OwnedHelperResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol OwnedHelperProcess: AnyObject, Sendable {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    var environment: [String: String]? { get set }
    var standardOutput: Any? { get set }
    var standardError: Any? { get set }
    var terminationStatus: Int32 { get }
    var processIdentifier: Int32 { get }

    func run() throws
    func waitUntilExit()
    func sendSignal(_ signal: Int32)
}

extension Process: OwnedHelperProcess {
    public func sendSignal(_ signal: Int32) {
        guard isRunning else { return }
        _ = Darwin.kill(processIdentifier, signal)
    }
}

public struct OwnedHelperRunner: Sendable {
    public typealias ProcessFactory = @Sendable () -> any OwnedHelperProcess

    private let processFactory: ProcessFactory

    public init(processFactory: @escaping ProcessFactory = { Process() }) {
        self.processFactory = processFactory
    }

    public func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        configuration: OwnedHelperConfiguration
    ) throws -> OwnedHelperResult {
        let process = processFactory()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutRead = OwnedFileHandle(stdoutPipe.fileHandleForReading)
        let stdoutWrite = OwnedFileHandle(stdoutPipe.fileHandleForWriting)
        let stderrRead = OwnedFileHandle(stderrPipe.fileHandleForReading)
        let stderrWrite = OwnedFileHandle(stderrPipe.fileHandleForWriting)
        let drainGroup = DispatchGroup()
        let stdoutCapture = StreamCapture(limit: max(0, configuration.outputLimit), group: drainGroup)
        let stderrCapture = StreamCapture(limit: max(0, configuration.outputLimit), group: drainGroup)
        let exit = ExitCoordinator()
        let waiter: @Sendable () -> Void = {
            process.waitUntilExit()
            exit.recordReaped()
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        installReader(handle: stdoutRead, capture: stdoutCapture)
        installReader(handle: stderrRead, capture: stderrCapture)

        do {
            try process.run()
        } catch {
            stdoutRead.stopReading()
            stderrRead.stopReading()
            stdoutWrite.close()
            stderrWrite.close()
            stdoutCapture.finish()
            stderrCapture.finish()
            throw OwnedHelperError.launchFailed(error.localizedDescription)
        }

        stdoutWrite.close()
        stderrWrite.close()
        DispatchQueue.global(qos: .userInitiated).async(execute: waiter)

        let naturalExit = exit.waitForExitOrClaimDeadline(
            after: bounded(configuration.timeout)
        )
        if !naturalExit {
            exit.signalIfUnreaped(process: process, signal: SIGTERM)
            if !exit.waitForReap(after: bounded(configuration.terminationGrace)) {
                exit.signalIfUnreaped(process: process, signal: SIGKILL)
                _ = exit.waitForReap(after: bounded(configuration.terminationGrace))
            }
            finishDraining(
                group: drainGroup,
                stdoutRead: stdoutRead,
                stderrRead: stderrRead,
                stdoutCapture: stdoutCapture,
                stderrCapture: stderrCapture,
                grace: bounded(configuration.postExitDrainGrace)
            )
            throw OwnedHelperError.timedOut
        }

        let drainedNaturally = finishDraining(
            group: drainGroup,
            stdoutRead: stdoutRead,
            stderrRead: stderrRead,
            stdoutCapture: stdoutCapture,
            stderrCapture: stderrCapture,
            grace: bounded(configuration.postExitDrainGrace)
        )
        let stdoutSnapshot = stdoutCapture.snapshot()
        let stderrSnapshot = stderrCapture.snapshot()

        guard drainedNaturally else {
            throw OwnedHelperError.pipeDrainTimedOut
        }

        var overflowingStreams: Set<OwnedHelperStream> = []
        if stdoutSnapshot.exceededLimit { overflowingStreams.insert(.stdout) }
        if stderrSnapshot.exceededLimit { overflowingStreams.insert(.stderr) }
        guard overflowingStreams.isEmpty else {
            throw OwnedHelperError.outputLimitExceeded(streams: overflowingStreams)
        }

        return OwnedHelperResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutSnapshot.data, as: UTF8.self),
            stderr: String(decoding: stderrSnapshot.data, as: UTF8.self)
        )
    }

    private func installReader(handle: OwnedFileHandle, capture: StreamCapture) {
        let readerQueue = DispatchQueue(
            label: "ptk.owned-helper.stream-reader",
            qos: .userInitiated
        )
        capture.start()
        handle.fileHandle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            readerQueue.async {
                if data.isEmpty {
                    handle.stopReading()
                    capture.finish()
                } else {
                    capture.append(data)
                }
            }
        }
    }

    @discardableResult
    private func finishDraining(
        group: DispatchGroup,
        stdoutRead: OwnedFileHandle,
        stderrRead: OwnedFileHandle,
        stdoutCapture: StreamCapture,
        stderrCapture: StreamCapture,
        grace: TimeInterval
    ) -> Bool {
        if group.wait(timeout: .now() + grace) == .success {
            return true
        }

        stdoutRead.stopReading()
        stderrRead.stopReading()
        stdoutCapture.finish()
        stderrCapture.finish()
        return false
    }

    private func bounded(_ interval: TimeInterval) -> TimeInterval {
        interval.isFinite ? max(0, interval) : 0
    }
}

private final class OwnedFileHandle: @unchecked Sendable {
    let fileHandle: FileHandle
    private let lock = NSLock()
    private var isClosed = false

    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func stopReading() {
        guard claimClose() else { return }
        fileHandle.readabilityHandler = nil
        fileHandle.closeFile()
    }

    func close() {
        guard claimClose() else { return }
        fileHandle.closeFile()
    }

    private func claimClose() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return false }
        isClosed = true
        return true
    }
}

private final class StreamCapture: @unchecked Sendable {
    private let limit: Int
    private let group: DispatchGroup
    private let lock = NSLock()
    private var data = Data()
    private var exceededLimit = false
    private var isStarted = false
    private var isFinished = false

    init(limit: Int, group: DispatchGroup) {
        self.limit = limit
        self.group = group
    }

    func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        group.enter()
        lock.unlock()
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }

        let remaining = limit - data.count
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            exceededLimit = true
        }
    }

    func finish() {
        lock.lock()
        guard isStarted, !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        lock.unlock()
        group.leave()
    }

    func snapshot() -> (data: Data, exceededLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, exceededLimit)
    }
}

private final class ExitCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let reapedSignal = DispatchSemaphore(value: 0)
    private var reaped = false
    private var deadlineWon = false

    func recordReaped() {
        lock.lock()
        guard !reaped else {
            lock.unlock()
            return
        }
        reapedSignal.signal()
        reaped = true
        lock.unlock()
    }

    func waitForExitOrClaimDeadline(after interval: TimeInterval) -> Bool {
        let signaled = reapedSignal.wait(timeout: .now() + interval) == .success
        lock.lock()
        if !signaled {
            deadlineWon = true
        }
        let exitedNaturally = reaped && !deadlineWon
        lock.unlock()
        return exitedNaturally
    }

    func waitForReap(after interval: TimeInterval) -> Bool {
        lock.lock()
        if reaped {
            lock.unlock()
            return true
        }
        lock.unlock()

        _ = reapedSignal.wait(timeout: .now() + interval)
        lock.lock()
        let result = reaped
        lock.unlock()
        return result
    }

    func signalIfUnreaped(process: any OwnedHelperProcess, signal: Int32) {
        lock.lock()
        guard !reaped else {
            lock.unlock()
            return
        }
        process.sendSignal(signal)
        lock.unlock()
    }
}
