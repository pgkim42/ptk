import Foundation

import Testing
@testable import PTKCore

@Suite struct MenuModelTests {
    @Test func emptyOpenPortsRenderEmptyState() {
        let model = MenuModel(statuses: [PortStatus(port: 3000, isOpen: false)])
        #expect(model.title == "PTK 0")
        #expect(model.isEmpty)
        #expect(model.refreshIntervals == [.oneSecond, .threeSeconds, .fiveSeconds, .tenSeconds])
    }

    @Test func openCountIncludesOnlyOpenWatchedPorts() {
        let model = MenuModel(statuses: [
            PortStatus(port: 3000, isOpen: true, pid: 100, processName: "node"),
            PortStatus(port: 3001, isOpen: false),
            PortStatus(port: 5173, isOpen: true, pid: 200, processName: "vite")
        ])

        #expect(model.title == "PTK 2")
        #expect(model.rows.map(\.port) == [3000, 5173])
    }

    @Test func rowsIncludePortPidAndProcessName() {
        let row = MenuModel(statuses: [
            PortStatus(port: 5173, isOpen: true, pid: 333, processName: "vite")
        ]).rows[0]

        #expect(row.displayText == "Port 5173 · PID 333 · vite")
        #expect(row.canRequestKill)
    }

    @Test func rowsWithoutSafeKillTargetCannotRequestKill() {
        let rows = MenuModel(statuses: [
            PortStatus(port: 3000, isOpen: true),
            PortStatus(port: 3001, isOpen: true, pid: 0, processName: "node"),
            PortStatus(port: 3002, isOpen: true, pid: 222)
        ]).rows

        #expect(rows.allSatisfy { !$0.canRequestKill })
    }

    @Test func rowsExposeWhyKillCannotBeRequested() {
        let rows = MenuModel(statuses: [
            PortStatus(port: 3000, isOpen: true),
            PortStatus(port: 3001, isOpen: true, pid: 222),
            PortStatus(
                port: 3002,
                isOpen: true,
                message: "ambiguous process lookup: port 3002 has PIDs 1, 2"
            ),
            PortStatus(port: 3003, isOpen: true, pid: 333, processName: "node"),
            PortStatus(port: 3004, isOpen: false)
        ]).rows

        #expect(rows[0].killUnavailableCause == .missingPID)
        #expect(rows[1].killUnavailableCause == .missingProcessName(pid: 222))
        #expect(rows[2].killUnavailableCause == .ambiguousListener(message: "ambiguous process lookup: port 3002 has PIDs 1, 2"))
        #expect(rows[3].killUnavailableCause == nil)
        #expect(rows.map(\.port) == [3000, 3001, 3002, 3003])
    }

    @Test func killUnavailableCauseExposesDomainDataSeparatelyFromText() {
        let ambiguous = PortStatus(
            port: 3002,
            isOpen: true,
            message: "ambiguous process lookup: port 3002 has PIDs 1, 2"
        )
        let lookupFailure = PortStatus(port: 3003, isOpen: true, message: "lsof failed")
        let missingPID = PortStatus(port: 3000, isOpen: true)
        let missingProcessName = PortStatus(port: 3001, isOpen: true, pid: 222)
        let safe = PortStatus(port: 3004, isOpen: true, pid: 333, processName: "node")

        #expect(ambiguous.killUnavailableCause == .ambiguousListener(message: "ambiguous process lookup: port 3002 has PIDs 1, 2"))
        #expect(lookupFailure.killUnavailableCause == .lookupFailed(message: "lsof failed"))
        #expect(missingPID.killUnavailableCause == .missingPID)
        #expect(missingProcessName.killUnavailableCause == .missingProcessName(pid: 222))
        #expect(safe.killUnavailableCause == nil)
    }

    @Test func verifiedIdentityValidatesAndPortStatusNormalizesIdentity() throws {
        let identity = try #require(VerifiedProcessIdentity(pid: 42, processName: "  node \n"))
        #expect(identity.pid == 42)
        #expect(identity.processName == "node")
        #expect(VerifiedProcessIdentity(pid: 0, processName: "node") == nil)
        #expect(VerifiedProcessIdentity(pid: 42, processName: " \n") == nil)

        let open = PortStatus(port: 3000, isOpen: true, identityState: .verified(identity))
        #expect(open.identityState == .verified(identity))
        #expect(open.verifiedIdentity == identity)
        #expect(open.pid == 42)
        #expect(open.processName == "node")
        #expect(open.message == nil)
        #expect(open.killTarget == KillTarget(port: 3000, pid: 42, processName: "node"))

        let legacyOpen = PortStatus(
            port: 3000,
            isOpen: true,
            pid: 42,
            processName: "  node \n"
        )
        #expect(legacyOpen.identityState == .verified(identity))
        #expect(legacyOpen.killTarget == open.killTarget)

        let openWithoutIdentity = PortStatus(port: 3001, isOpen: true, identityState: nil)
        #expect(openWithoutIdentity.identityState == .unavailable(.noVerifiedListener))
        #expect(openWithoutIdentity.killTarget == nil)

        let closed = PortStatus(port: 3002, isOpen: false, identityState: .verified(identity))
        #expect(closed.identityState == nil)
        #expect(closed.verifiedIdentity == nil)
        #expect(closed.pid == nil)
        #expect(closed.processName == nil)
        #expect(closed.message == nil)
        #expect(closed.killTarget == nil)
    }

    @Test func menuRowNeverBuildsKillTargetFromUnavailableIdentityProjections() {
        let status = PortStatus(
            port: 3000,
            isOpen: true,
            identityState: .unavailable(.processNameUnavailable(pid: 42))
        )

        let row = PortMenuRow(status: status)

        #expect(status.pid == nil)
        #expect(status.processName == nil)
        #expect(row.pid == nil)
        #expect(row.processName == nil)
        #expect(row.killTarget == nil)
        #expect(!row.canRequestKill)
        #expect(row.killUnavailableCause == .missingProcessName(pid: 42))
    }

    @Test func portChangeBaselineRetainsVerifiedIdentityThroughUnavailableSamples() throws {
        let identityA = try #require(VerifiedProcessIdentity(pid: 10, processName: "node"))
        let identityB = try #require(VerifiedProcessIdentity(pid: 20, processName: "vite"))
        let verifiedA = PortStatus(port: 3000, isOpen: true, identityState: .verified(identityA))
        let verifiedB = PortStatus(port: 3000, isOpen: true, identityState: .verified(identityB))
        let lookupFailure = PortStatus(
            port: 3000,
            isOpen: true,
            identityState: .unavailable(.lookupFailed(message: "lsof failed"))
        )
        let ambiguity = PortStatus(
            port: 3000,
            isOpen: true,
            identityState: .unavailable(.ambiguousListeners(pids: [10, 20]))
        )

        #expect(PortChange.detect(previous: [verifiedA], current: [lookupFailure]).isEmpty)
        let afterFailure = PortChange.mergedBaseline(previous: [verifiedA], current: [lookupFailure])
        #expect(afterFailure == [verifiedA])

        #expect(PortChange.detect(previous: afterFailure, current: [verifiedA]).isEmpty)
        let afterRecovery = PortChange.mergedBaseline(previous: afterFailure, current: [verifiedA])
        #expect(afterRecovery == [verifiedA])

        #expect(PortChange.detect(previous: afterRecovery, current: [ambiguity]).isEmpty)
        let afterAmbiguity = PortChange.mergedBaseline(previous: afterRecovery, current: [ambiguity])
        #expect(afterAmbiguity == [verifiedA])
        #expect(PortChange.detect(previous: [ambiguity], current: [verifiedB]).isEmpty)

        let changes = PortChange.detect(previous: afterAmbiguity, current: [verifiedB])
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .changed)
        #expect(changes.first?.pid == 20)
        #expect(changes.first?.processName == "vite")
    }

    @Test func portChangesDetectOpenClosedAndProcessUpdates() {
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = [
            PortStatus(port: 3000, isOpen: false),
            PortStatus(port: 3001, isOpen: true, pid: 10, processName: "node"),
            PortStatus(port: 3002, isOpen: true, pid: 20, processName: "vite")
        ]
        let current = [
            PortStatus(port: 3000, isOpen: true, pid: 30, processName: "rails"),
            PortStatus(port: 3001, isOpen: false),
            PortStatus(port: 3002, isOpen: true, pid: 21, processName: "vite")
        ]

        let changes = PortChange.detect(previous: previous, current: current, occurredAt: occurredAt)

        #expect(changes.map(\.kind) == [.opened, .closed, .changed])
        #expect(changes.map(\.port) == [3000, 3001, 3002])
        #expect(changes.map(\.pid) == [30, nil, 21])
        #expect(changes.map(\.processName) == ["rails", nil, "vite"])
        #expect(changes.allSatisfy { $0.occurredAt == occurredAt })
    }

    @Test func portChangeIdentityIncludesOccurrenceTime() {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_060)

        let first = PortChange(port: 3000, kind: .opened, pid: 30, processName: "node", occurredAt: firstDate)
        let repeated = PortChange(port: 3000, kind: .opened, pid: 30, processName: "node", occurredAt: secondDate)
        let sameAsFirst = PortChange(port: 3000, kind: .opened, pid: 30, processName: "node", occurredAt: firstDate)

        #expect(first.id != repeated.id)
        #expect(first == sameAsFirst)
        #expect(first != repeated)
        #expect(PortChange(port: 3000, kind: .opened, occurredAt: firstDate).id !=
            PortChange(port: 3000, kind: .opened, pid: 0, processName: "", occurredAt: firstDate).id)
    }

    @Test func errorStateDoesNotHideRows() {
        let model = MenuModel(
            statuses: [PortStatus(port: 3000, isOpen: true, pid: 111, processName: "node")],
            errorMessage: "lookup failed"
        )

        #expect(model.errorMessage == "lookup failed")
        #expect(model.rows.count == 1)
    }
}
