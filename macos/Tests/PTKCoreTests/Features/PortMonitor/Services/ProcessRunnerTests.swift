import Darwin
import Dispatch
import Foundation
import Testing
@testable import PTKCore

@Suite(.serialized) struct ProcessRunnerTests {
    @Test func configurationHasPinnedDefaults() {
        let configuration = OwnedHelperConfiguration(timeout: 1)

        #expect(configuration.timeout == 1)
        #expect(configuration.outputLimit == 4 * 1_024 * 1_024)
        #expect(configuration.terminationGrace == 0.25)
        #expect(configuration.postExitDrainGrace == 0.25)
    }

    @Test func drainsLargeStdoutAndStderrWithoutPipeDeadlock() throws {
        let process = FakeOwnedHelperProcess(
            exitBehavior: .immediate,
            outputByteCount: 1_048_576,
            errorOutputByteCount: 1_048_576
        )
        let result = try OwnedHelperRunner(processFactory: { process }).run(
            "/fake/helper",
            arguments: [],
            configuration: OwnedHelperConfiguration(timeout: 5)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count == 1_048_576)
        #expect(result.stderr.utf8.count == 1_048_576)
    }

    @Test(arguments: [
        (2_048, 0, Set([OwnedHelperStream.stdout])),
        (0, 2_048, Set([OwnedHelperStream.stderr])),
        (2_048, 2_048, Set([OwnedHelperStream.stdout, OwnedHelperStream.stderr]))
    ])
    func reportsEveryOverflowingStream(
        stdoutByteCount: Int,
        stderrByteCount: Int,
        streams: Set<OwnedHelperStream>
    ) {
        let process = FakeOwnedHelperProcess(
            exitBehavior: .immediate,
            outputByteCount: stdoutByteCount,
            errorOutputByteCount: stderrByteCount
        )

        #expect(throws: OwnedHelperError.outputLimitExceeded(streams: streams)) {
            try OwnedHelperRunner(processFactory: { process }).run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(timeout: 2, outputLimit: 1_024)
            )
        }
    }

    @Test func deadlineRecordedBeforeExitWinsOverOutputOverflow() {
        let process = FakeOwnedHelperProcess(exitBehavior: .onKill, outputByteCount: 2_048)

        #expect(throws: OwnedHelperError.timedOut) {
            try OwnedHelperRunner(processFactory: { process }).run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.03,
                    outputLimit: 1_024,
                    terminationGrace: 0.03,
                    postExitDrainGrace: 0.03
                )
            )
        }
        #expect(process.signals == [SIGTERM, SIGKILL])
    }

    @Test func termCooperativeChildReceivesOnlyTerm() {
        let process = FakeOwnedHelperProcess(exitBehavior: .onTerm)
        let runner = OwnedHelperRunner(processFactory: { process })

        #expect(throws: OwnedHelperError.timedOut) {
            try runner.run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.01,
                    terminationGrace: 0.05,
                    postExitDrainGrace: 0.01
                )
            )
        }
        #expect(process.signals == [SIGTERM])
        #expect(process.waitUntilExitCallCount == 1)
    }

    @Test func termIgnoringChildReceivesTermThenKill() {
        let process = FakeOwnedHelperProcess(exitBehavior: .onKill)
        let runner = OwnedHelperRunner(processFactory: { process })

        #expect(throws: OwnedHelperError.timedOut) {
            try runner.run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.01,
                    terminationGrace: 0.01,
                    postExitDrainGrace: 0.01
                )
            )
        }
        #expect(process.signals == [SIGTERM, SIGKILL])
        #expect(process.waitUntilExitCallCount == 1)
    }

    @Test func exactlyOneWaiterOwnsNaturalReap() throws {
        let process = FakeOwnedHelperProcess(exitBehavior: .immediate)
        let result = try OwnedHelperRunner(processFactory: { process }).run(
            "/fake/helper",
            arguments: [],
            configuration: OwnedHelperConfiguration(timeout: 0.2)
        )

        #expect(result.exitCode == 0)
        #expect(process.waitUntilExitCallCount == 1)
        #expect(process.signals.isEmpty)
        #expect(process.parentPipeHandlesAreClosed())
    }

    @Test func launchFailureClosesAllParentHandlesWithoutStartingWaiter() {
        let process = FakeOwnedHelperProcess(exitBehavior: .immediate, launchError: FixtureError.launch)

        #expect(throws: OwnedHelperError.self) {
            try OwnedHelperRunner(processFactory: { process }).run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(timeout: 0.1)
            )
        }

        #expect(process.waitUntilExitCallCount == 0)
        #expect(process.parentPipeHandlesAreClosed())
    }

    @Test func systemRunnerMapsPipeDrainTimeout() {
        let process = FakeOwnedHelperProcess(exitBehavior: .immediate, holdsOutputDescriptor: true)
        let runner = SystemProcessRunner(helperRunner: OwnedHelperRunner(processFactory: { process }))

        #expect(throws: ProcessRunnerError.pipeDrainTimedOut) {
            try runner.run("ignored", arguments: [], timeout: 1)
        }
        process.closeHeldDescriptor()
    }

}

private enum FixtureError: Error {
    case launch
}

private final class FakeOwnedHelperProcess: OwnedHelperProcess, @unchecked Sendable {
    enum ExitBehavior: Equatable {
        case immediate
        case onTerm
        case onKill
    }

    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    var processIdentifier: Int32 { 42_424 }

    var terminationStatus: Int32 {
        lock.withLock { storedTerminationStatus }
    }

    var signals: [Int32] {
        lock.withLock { receivedSignals }
    }

    var waitUntilExitCallCount: Int {
        lock.withLock { waitCallCount }
    }

    private let exitBehavior: ExitBehavior
    private let launchError: Error?
    private let holdsOutputDescriptor: Bool
    private let outputByteCount: Int
    private let errorOutputByteCount: Int
    private let lock = NSLock()
    private let exitSemaphore = DispatchSemaphore(value: 0)
    private let storedTerminationStatus: Int32
    private var receivedSignals: [Int32] = []
    private var waitCallCount = 0
    private var heldDescriptor: Int32 = -1
    private var capturedOutputPipe: Pipe?
    private var capturedErrorPipe: Pipe?
    private var parentPipeDescriptors: [Int32] = []

    init(
        exitBehavior: ExitBehavior,
        holdsOutputDescriptor: Bool = false,
        outputByteCount: Int = 0,
        errorOutputByteCount: Int = 0,
        exitCode: Int32 = 0,
        launchError: Error? = nil
    ) {
        self.exitBehavior = exitBehavior
        self.holdsOutputDescriptor = holdsOutputDescriptor
        self.outputByteCount = outputByteCount
        self.errorOutputByteCount = errorOutputByteCount
        storedTerminationStatus = exitCode
        self.launchError = launchError
    }

    func run() throws {
        capturedOutputPipe = standardOutput as? Pipe
        capturedErrorPipe = standardError as? Pipe
        if let capturedOutputPipe, let capturedErrorPipe {
            parentPipeDescriptors = [
                capturedOutputPipe.fileHandleForReading.fileDescriptor,
                capturedOutputPipe.fileHandleForWriting.fileDescriptor,
                capturedErrorPipe.fileHandleForReading.fileDescriptor,
                capturedErrorPipe.fileHandleForWriting.fileDescriptor
            ]
        }
        if let launchError { throw launchError }

        if holdsOutputDescriptor, let outputPipe = capturedOutputPipe {
            heldDescriptor = Darwin.dup(outputPipe.fileHandleForWriting.fileDescriptor)
        }
        if outputByteCount > 0, let outputPipe = capturedOutputPipe {
            outputPipe.fileHandleForWriting.write(Data(repeating: 65, count: outputByteCount))
        }
        if errorOutputByteCount > 0, let errorPipe = capturedErrorPipe {
            errorPipe.fileHandleForWriting.write(Data(repeating: 66, count: errorOutputByteCount))
        }
        if exitBehavior == .immediate {
            exitSemaphore.signal()
        }
    }

    func waitUntilExit() {
        lock.withLock { waitCallCount += 1 }
        _ = exitSemaphore.wait(timeout: .now() + 1)
    }

    func sendSignal(_ signal: Int32) {
        lock.withLock { receivedSignals.append(signal) }
        if (signal == SIGTERM && exitBehavior == .onTerm) || signal == SIGKILL {
            exitSemaphore.signal()
        }
    }

    func closeHeldDescriptor() {
        lock.withLock {
            guard heldDescriptor >= 0 else { return }
            Darwin.close(heldDescriptor)
            heldDescriptor = -1
        }
    }

    func parentPipeHandlesAreClosed() -> Bool {
        parentPipeDescriptors.count == 4 && parentPipeDescriptors.allSatisfy(isClosed)
    }

    private func isClosed(_ descriptor: Int32) -> Bool {
        errno = 0
        return Darwin.fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
    }
}
