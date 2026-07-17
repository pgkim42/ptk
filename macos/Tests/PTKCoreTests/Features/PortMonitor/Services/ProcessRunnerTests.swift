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
        let result = try OwnedHelperRunner().run(
            "/bin/sh",
            arguments: [
                "-c",
                "dd if=/dev/zero bs=1048576 count=1 2>/dev/null & dd if=/dev/zero bs=1048576 count=1 1>&2 2>/dev/null; wait"
            ],
            configuration: OwnedHelperConfiguration(timeout: 5)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count == 1_048_576)
        #expect(result.stderr.utf8.count == 1_048_576)
    }

    @Test(arguments: [
        ("dd if=/dev/zero bs=2048 count=1 2>/dev/null", Set([OwnedHelperStream.stdout])),
        ("dd if=/dev/zero bs=2048 count=1 1>&2 2>/dev/null", Set([OwnedHelperStream.stderr])),
        (
            "dd if=/dev/zero bs=2048 count=1 2>/dev/null & dd if=/dev/zero bs=2048 count=1 1>&2 2>/dev/null; wait",
            Set([OwnedHelperStream.stdout, OwnedHelperStream.stderr])
        )
    ])
    func reportsEveryOverflowingStream(command: String, streams: Set<OwnedHelperStream>) {
        #expect(throws: OwnedHelperError.outputLimitExceeded(streams: streams)) {
            try OwnedHelperRunner().run(
                "/bin/sh",
                arguments: ["-c", command],
                configuration: OwnedHelperConfiguration(timeout: 2, outputLimit: 1_024)
            )
        }
    }

    @Test func launchFailureIsTyped() {
        #expect(throws: OwnedHelperError.self) {
            try OwnedHelperRunner().run(
                "/path/that/does/not/exist",
                arguments: [],
                configuration: OwnedHelperConfiguration(timeout: 0.1)
            )
        }
    }

    @Test func naturalExitRecordedBeforeDeadlineWins() throws {
        let result = try OwnedHelperRunner().run(
            "/bin/sh",
            arguments: ["-c", "exit 7"],
            configuration: OwnedHelperConfiguration(timeout: 1)
        )

        #expect(result.exitCode == 7)
    }

    @Test func deadlineRecordedBeforeExitWinsOverOutputOverflow() {
        #expect(throws: OwnedHelperError.timedOut) {
            try OwnedHelperRunner().run(
                "/bin/sh",
                arguments: ["-c", "dd if=/dev/zero bs=2048 count=1 2>/dev/null; while :; do :; done"],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.03,
                    outputLimit: 1_024,
                    terminationGrace: 0.03,
                    postExitDrainGrace: 0.03
                )
            )
        }
    }
    @Test func coordinatedExitRecordedBeforeDeadlineReturnsNormally() throws {
        let process = BoundaryOwnedHelperProcess(exitBoundary: .afterWaiterStarts)
        let result = try OwnedHelperRunner(processFactory: { process }).run(
            "/fake/helper",
            arguments: [],
            configuration: OwnedHelperConfiguration(timeout: 5, postExitDrainGrace: 0.1)
        )

        #expect(result.exitCode == 17)
        #expect(process.didCoordinateExitAfterWaiterStarted)
        #expect(process.waitUntilExitCallCount == 1)
        #expect(process.signals.isEmpty)
    }

    @Test func coordinatedDeadlineClaimBeforeNearImmediateExitReturnsTimedOut() {
        let process = BoundaryOwnedHelperProcess(exitBoundary: .afterDeadlineSignal)

        #expect(throws: OwnedHelperError.timedOut) {
            try OwnedHelperRunner(processFactory: { process }).run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.01,
                    terminationGrace: 0.5,
                    postExitDrainGrace: 0.1
                )
            )
        }

        #expect(process.didReleaseExitAfterDeadlineSignal)
        #expect(process.waitUntilExitCallCount == 1)
        #expect(process.signals == [SIGTERM])
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

    @Test func timedOutRealChildIsReapedAfterKillEscalation() {
        let process = Process()
        let runner = OwnedHelperRunner(processFactory: { process })

        #expect(throws: OwnedHelperError.timedOut) {
            try runner.run(
                "/bin/sh",
                arguments: ["-c", "trap '' TERM; while :; do :; done"],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.02,
                    terminationGrace: 0.02,
                    postExitDrainGrace: 0.02
                )
            )
        }

        var status: Int32 = 0
        errno = 0
        #expect(Darwin.waitpid(process.processIdentifier, &status, WNOHANG) == -1)
        #expect(errno == ECHILD)
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

    @Test func descendantHeldDescriptorsProduceBoundedDrainFailure() {
        let process = FakeOwnedHelperProcess(exitBehavior: .immediate, holdsOutputDescriptor: true)
        let start = ContinuousClock.now

        #expect(throws: OwnedHelperError.pipeDrainTimedOut) {
            try OwnedHelperRunner(processFactory: { process }).run(
                "/fake/helper",
                arguments: [],
                configuration: OwnedHelperConfiguration(timeout: 0.2, postExitDrainGrace: 0.02)
            )
        }
        #expect(ContinuousClock.now - start < .seconds(1))
        process.closeHeldDescriptor()
    }
    @Test func realDescendantHeldDescriptorsProduceBoundedDrainFailure() throws {
        let fixture = try TestOwnedDescendantFixture()
        defer { fixture.cleanup() }
        let start = ContinuousClock.now

        #expect(throws: OwnedHelperError.pipeDrainTimedOut) {
            try OwnedHelperRunner().run(
                "/bin/sh",
                arguments: [
                    "-c",
                    "(trap 'exit 0' TERM; while [ -e \"$2\" ]; do :; done) & printf '%s' \"$!\" > \"$1\"",
                    "descriptor-holder",
                    fixture.pidFileURL.path,
                    fixture.keepAliveURL.path
                ],
                configuration: OwnedHelperConfiguration(timeout: 1, postExitDrainGrace: 0.05)
            )
        }

        #expect(ContinuousClock.now - start < .seconds(1))
        let descendantIsAlive = try fixture.recordedDescendantIsAlive()
        #expect(descendantIsAlive)
    }

    @Test func realTimeoutEscalationLeavesRecordedDescendantAlive() throws {
        let fixture = try TestOwnedDescendantFixture()
        defer { fixture.cleanup() }
        let directChild = Process()

        #expect(throws: OwnedHelperError.timedOut) {
            try OwnedHelperRunner(processFactory: { directChild }).run(
                "/bin/sh",
                arguments: [
                    "-c",
                    "trap ':' TERM; (trap 'exit 0' TERM; : > \"$3\"; while [ -e \"$2\" ]; do :; done) & descendant=$!; printf '%s' \"$descendant\" > \"$1\"; while [ ! -e \"$3\" ]; do :; done; while :; do :; done",
                    "direct-child-only",
                    fixture.pidFileURL.path,
                    fixture.keepAliveURL.path,
                    fixture.readyURL.path,
                ],
                configuration: OwnedHelperConfiguration(
                    timeout: 0.1,
                    terminationGrace: 0.05,
                    postExitDrainGrace: 0.05
                )
            )
        }

        let descendantPID = try fixture.recordedPID()
        #expect(descendantPID != directChild.processIdentifier)
        #expect(fixture.isAlive(descendantPID))
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

    @Test func systemRunnerMapsLaunchFailure() {
        let process = FakeOwnedHelperProcess(exitBehavior: .immediate, launchError: FixtureError.launch)
        let runner = SystemProcessRunner(helperRunner: OwnedHelperRunner(processFactory: { process }))

        #expect(throws: ProcessRunnerError.launchFailed(FixtureError.launch.localizedDescription)) {
            try runner.run("ignored", arguments: [], timeout: 0.1)
        }
    }

    @Test func systemRunnerMapsTimeout() {
        let process = FakeOwnedHelperProcess(exitBehavior: .onKill)
        let runner = SystemProcessRunner(helperRunner: OwnedHelperRunner(processFactory: { process }))

        #expect(throws: ProcessRunnerError.timedOut) {
            try runner.run("ignored", arguments: [], timeout: 0.01)
        }
    }

    @Test func systemRunnerMapsOutputOverflow() {
        let process = FakeOwnedHelperProcess(
            exitBehavior: .immediate,
            outputByteCount: OwnedHelperConfiguration.defaultOutputLimit + 1
        )
        let runner = SystemProcessRunner(helperRunner: OwnedHelperRunner(processFactory: { process }))

        #expect(throws: ProcessRunnerError.outputLimitExceeded(streams: [.stdout])) {
            try runner.run("ignored", arguments: [], timeout: 2)
        }
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

private final class BoundaryOwnedHelperProcess: OwnedHelperProcess, @unchecked Sendable {
    enum ExitBoundary: Equatable {
        case afterWaiterStarts
        case afterDeadlineSignal
    }

    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    let processIdentifier: Int32 = 43_434
    let terminationStatus: Int32 = 17

    var signals: [Int32] {
        condition.withLock { receivedSignals }
    }

    var waitUntilExitCallCount: Int {
        condition.withLock { waitCallCount }
    }

    var didCoordinateExitAfterWaiterStarted: Bool {
        condition.withLock { coordinatedExitAfterWaiterStarted }
    }

    var didReleaseExitAfterDeadlineSignal: Bool {
        condition.withLock { releasedExitAfterDeadlineSignal }
    }

    private let exitBoundary: ExitBoundary
    private let condition = NSCondition()
    private var receivedSignals: [Int32] = []
    private var waitCallCount = 0
    private var waiterStarted = false
    private var shouldExit = false
    private var coordinatedExitAfterWaiterStarted = false
    private var releasedExitAfterDeadlineSignal = false

    init(exitBoundary: ExitBoundary) {
        self.exitBoundary = exitBoundary
    }

    func run() throws {
        guard exitBoundary == .afterWaiterStarts else { return }

        DispatchQueue.global(qos: .utility).async { [self] in
            condition.lock()
            while !waiterStarted {
                condition.wait()
            }
            coordinatedExitAfterWaiterStarted = true
            shouldExit = true
            condition.broadcast()
            condition.unlock()
        }
    }

    func waitUntilExit() {
        condition.lock()
        waitCallCount += 1
        waiterStarted = true
        condition.broadcast()
        while !shouldExit {
            condition.wait()
        }
        condition.unlock()
    }

    func sendSignal(_ signal: Int32) {
        condition.lock()
        receivedSignals.append(signal)
        if exitBoundary == .afterDeadlineSignal, signal == SIGTERM {
            releasedExitAfterDeadlineSignal = true
            shouldExit = true
            condition.broadcast()
        } else if signal == SIGKILL {
            shouldExit = true
            condition.broadcast()
        }
        condition.unlock()
    }
}

private final class TestOwnedDescendantFixture {
    let pidFileURL: URL
    let keepAliveURL: URL
    let readyURL: URL

    private let directoryURL: URL

    init() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptk-process-runner-\(UUID().uuidString)", isDirectory: true)
        self.directoryURL = directoryURL
        pidFileURL = directoryURL.appendingPathComponent("descendant.pid")
        keepAliveURL = directoryURL.appendingPathComponent("keep-alive")
        readyURL = directoryURL.appendingPathComponent("descendant-ready")
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false
            )
            guard FileManager.default.createFile(atPath: keepAliveURL.path, contents: Data()) else {
                throw FixtureError.fixtureCreationFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    func recordedPID() throws -> Int32 {
        let data = try Data(contentsOf: pidFileURL)
        let contents = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(contents), pid > 1 else {
            throw FixtureError.invalidDescendantPID
        }
        return pid
    }

    func recordedDescendantIsAlive() throws -> Bool {
        isAlive(try recordedPID())
    }

    func isAlive(_ pid: Int32) -> Bool {
        errno = 0
        return Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    func cleanup() {
        let pid = try? recordedPID()
        try? FileManager.default.removeItem(at: keepAliveURL)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        guard let pid else { return }
        for _ in 0..<50 where isAlive(pid) {
            Darwin.usleep(10_000)
        }
        guard isAlive(pid) else { return }

        _ = Darwin.kill(pid, SIGTERM)
        for _ in 0..<50 where isAlive(pid) {
            Darwin.usleep(10_000)
        }
        if isAlive(pid) {
            _ = Darwin.kill(pid, SIGKILL)
            for _ in 0..<50 where isAlive(pid) {
                Darwin.usleep(10_000)
            }
        }
    }
}

private enum FixtureError: Error {
    case fixtureCreationFailed
    case invalidDescendantPID
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
    private let lock = NSLock()
    private let exitSemaphore = DispatchSemaphore(value: 0)
    private var storedTerminationStatus: Int32 = 0
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
        launchError: Error? = nil
    ) {
        self.exitBehavior = exitBehavior
        self.holdsOutputDescriptor = holdsOutputDescriptor
        self.outputByteCount = outputByteCount
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
        if exitBehavior == .immediate {
            exitSemaphore.signal()
        }
    }

    func waitUntilExit() {
        lock.withLock { waitCallCount += 1 }
        exitSemaphore.wait()
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
