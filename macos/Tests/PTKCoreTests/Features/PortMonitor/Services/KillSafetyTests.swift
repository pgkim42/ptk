import Testing
@testable import PTKCore

struct FakeResolver: ProcessResolving {
    var info: PortProcessInfo?
    var error: Error?

    func info(for port: UInt16) throws -> PortProcessInfo? {
        if let error { throw error }
        return info
    }
}

final class FakeTerminator: ProcessTerminating {
    var terminatedPIDs: [Int] = []
    var failureMessage: String?

    func terminate(pid: Int) -> String? {
        terminatedPIDs.append(pid)
        return failureMessage
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
