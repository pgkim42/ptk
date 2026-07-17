import Foundation
import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
@Suite(.serialized)
struct PortChangeNotificationCoordinatorTests {
    @Test func reliableBaselineTruthTablePreservesUnreliableObservations() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [unreliable(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 10, "one")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.map(\.kind) == [.opened])

        coordinator.accept(harness.snapshot(1, watched: [3000], [verified(3000, 20, "two")]))
        coordinator.observe(harness.snapshot(1, watched: [3000], [unreliable(3000)]))
        coordinator.observe(harness.snapshot(1, watched: [3000], [closed(3000)]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.map(\.kind) == [.opened, .closed])
    }

    @Test func pidOnlyIsReliableButOtherOpenStatesAreNot() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [pidOnly(3000, 44)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [unreliable(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [pidOnly(3000, 44)]))
        await settle(coordinator)
        #expect(harness.delivery.candidates == [PortChangeNotificationCandidate(port: 3000, kind: .opened, pid: 44, processName: nil)])
    }

    @Test func equalWatchCommitPreservesEpochAndQueuedDelivery() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.delivery.gate = gate
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "a")]))
        coordinator.commitWatchedPorts([3000])

        #expect(coordinator.watchedEpoch == 0)
        await gate.open()
        await settle(coordinator)
        #expect(harness.delivery.candidates.count == 1)
    }

    @Test func watchCommitInvalidatesQueuedWorkAndReaddIsBaselineOnly() async {
        let harness = Harness()
        harness.permission.status = .notDetermined
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "a")]))
        coordinator.commitWatchedPorts([])
        coordinator.commitWatchedPorts([3000])
        coordinator.accept(harness.snapshot(1, epoch: coordinator.watchedEpoch, watched: [3000], [verified(3000, 1, "a")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.isEmpty)
    }

    @Test func rejectsStaleAndCorruptSnapshotsAndRechecksDeliveryEligibility() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(1, watched: [3000], [verified(3000, 1, "a")]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "a"), verified(3000, 2, "b")]))
        harness.eligibility.selectedNotificationPorts = []
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 3, "c")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.isEmpty)
    }

    @Test func identityOnlyOpenChangesDoNotNotify() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "a")]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 2, "b")]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [pidOnly(3000, 3)]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.map(\.kind) == [.opened])
    }

    @Test func successfulHandoffRecordsSuppressionAcrossEligibilityAndWatchChanges() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.delivery.gate = gate
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "a")]))
        await gate.waitForWaiter()

        coordinator.commitWatchedPorts([])
        harness.eligibility.selectedNotificationPorts = []
        harness.eligibility.notificationsEnabled = false
        harness.eligibility.notificationEligibilityRevision &+= 1
        coordinator.commitWatchedPorts([3000])
        harness.eligibility.selectedNotificationPorts = [3000]
        harness.eligibility.notificationsEnabled = true
        await gate.open()
        await settle(coordinator)

        coordinator.accept(harness.snapshot(1, epoch: coordinator.watchedEpoch, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(1, epoch: coordinator.watchedEpoch, watched: [3000], [verified(3000, 2, "b")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.count == 1)
    }

    @Test func preservesFIFOAcrossIndependentPortsAndOnlyRecordsSuccessfulHandoffs() async {
        let harness = Harness()
        harness.delivery.failNext = true
        let coordinator = harness.coordinator(watched: [3000, 3001])
        coordinator.accept(harness.snapshot(0, watched: [3000, 3001], [closed(3000), closed(3001)]))
        coordinator.observe(harness.snapshot(0, watched: [3000, 3001], [verified(3000, 1, "a"), verified(3001, 2, "b")]))
        await settle(coordinator)
        #expect(harness.delivery.attempts.map(\.port) == [3000, 3001])
        #expect(harness.delivery.candidates.map(\.port) == [3001])
    }

    @Test func newerPermissionOperationJoinsPromptAndPublishesTerminalStatus() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.permission.status = .notDetermined
        harness.permission.requestResult = .authorized
        harness.permission.requestGate = gate
        let coordinator = harness.coordinator(watched: [3000])

        async let first: Void = coordinator.requestPermissionIfNeeded()
        await gate.waitForWaiter()
        async let newer: Void = coordinator.requestPermissionIfNeeded()
        await gate.waitForWaiter()
        #expect(harness.permission.requestCount == 1)

        await gate.open()
        _ = await (first, newer)

        #expect(harness.permission.requestCount == 1)
        #expect(coordinator.permissionStatus == .authorized)
    }
    @Test func permissionRequestSurvivesPassiveRefreshAndPublishesItsTerminalError() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.permission.status = .notDetermined
        harness.permission.requestGate = gate
        harness.permission.shouldThrow = true
        let coordinator = harness.coordinator(watched: [3000])

        async let request: Void = coordinator.requestPermissionIfNeeded()
        await gate.waitForWaiter()
        await coordinator.refreshPermissionStatus()
        await gate.open()
        await request

        #expect(harness.permission.requestCount == 1)
        #expect(coordinator.permissionStatus == .notDetermined)
        #expect(coordinator.lastPermissionRequestError != nil)
    }

    @Test func permissionRequestSurvivesPassiveDeliveryReadWithoutDuplicatePrompt() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.permission.status = .notDetermined
        harness.permission.requestResult = .authorized
        harness.permission.requestGate = gate
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        async let first: Void = coordinator.requestPermissionIfNeeded()
        await gate.waitForWaiter()
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await settle(coordinator)
        async let joined: Void = coordinator.requestPermissionIfNeeded()

        await gate.open()
        _ = await (first, joined)

        #expect(harness.permission.requestCount == 1)
        #expect(coordinator.permissionStatus == .authorized)
        #expect(harness.delivery.attempts.isEmpty)
    }

    @Test func revokedPermissionBlocksDeliveryAndRestorationDeliversWithoutResave() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        harness.permission.status = .denied
        await coordinator.refreshPermissionStatus()
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await settle(coordinator)

        #expect(coordinator.permissionStatus == .denied)
        #expect(harness.eligibility.notificationsEnabled)
        #expect(harness.delivery.attempts.isEmpty)

        harness.permission.status = .authorized
        await coordinator.refreshPermissionStatus()
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await settle(coordinator)

        #expect(coordinator.permissionStatus == .authorized)
        #expect(harness.delivery.candidates.map(\.kind) == [.closed])
    }
    @Test func permissionRefreshAndRequestsHandleDenyUnknownAndStop() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        harness.permission.status = .denied
        await coordinator.refreshPermissionStatus()
        #expect(coordinator.permissionStatus == .denied)
        await coordinator.requestPermissionIfNeeded()
        #expect(coordinator.permissionStatus == .denied)
        #expect(harness.permission.requestCount == 0)
        harness.permission.status = .unknown
        await coordinator.requestPermissionIfNeeded()
        #expect(harness.permission.requestCount == 0)
        coordinator.stop()
        harness.permission.status = .notDetermined
        await coordinator.requestPermissionIfNeeded()
        #expect(harness.permission.requestCount == 0)
    }
    @Test func invalidatedConsentBeforeStatusReadReturnsDoesNotPrompt() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.permission.status = .notDetermined
        harness.permission.statusGate = gate
        let coordinator = harness.coordinator(watched: [3000])

        async let request: Void = coordinator.requestPermissionIfNeeded()
        await gate.waitForWaiter()
        harness.eligibility.notificationsEnabled = false
        harness.eligibility.notificationEligibilityRevision &+= 1
        await gate.open()
        await request

        #expect(harness.permission.requestCount == 0)
    }

    @Test func passivePermissionRefreshDoesNotConsumeAuthorizedDelivery() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.permission.status = .authorized
        harness.permission.statusGate = gate
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await gate.waitForWaiter()
        async let refresh: Void = coordinator.refreshPermissionStatus()
        await gate.open()
        await refresh
        await settle(coordinator)

        #expect(harness.delivery.attempts.count == 1)
        #expect(harness.delivery.candidates.count == 1)
    }
    @Test func consentRestorationInvalidatesQueuedDelivery() async {
        let harness = Harness()
        let gate = AsyncGate()
        harness.permission.statusGate = gate
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "a")]))
        await gate.waitForWaiter()

        harness.eligibility.notificationsEnabled = false
        harness.eligibility.notificationEligibilityRevision &+= 1
        harness.eligibility.notificationsEnabled = true
        harness.eligibility.notificationEligibilityRevision &+= 1
        await gate.open()
        await settle(coordinator)

        #expect(harness.delivery.attempts.isEmpty)
    }
    @Test func permissionRequestFailurePublishesTerminalStatusAndPreservesError() async {
        let harness = Harness()
        harness.permission.status = .notDetermined
        harness.permission.shouldThrow = true
        let coordinator = harness.coordinator(watched: [3000])

        await coordinator.requestPermissionIfNeeded()

        #expect(coordinator.permissionStatus == .notDetermined)
        #expect(coordinator.lastPermissionRequestError != nil)
    }
    @Test func suppressionUsesExactBoundaryAndDoesNotMaskOppositeDirection() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await settle(coordinator)

        harness.clock.time = 1
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await settle(coordinator)

        #expect(harness.delivery.candidates.map(\.kind) == [.opened, .closed])
    }

    @Test func suppressionBlocksAtNinePointNineNineNineAndAllowsAtTen() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await settle(coordinator)

        harness.delivery.failuresRemaining = 1
        harness.clock.time = 1
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await settle(coordinator)

        harness.clock.time = 9.999
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 2, "node")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.map(\.kind) == [.opened])

        harness.delivery.failuresRemaining = 1
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await settle(coordinator)

        harness.clock.time = 10
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 3, "node")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.map(\.kind) == [.opened, .opened])
    }

    @Test func failedSameDirectionHandoffDoesNotStartSuppression() async {
        let harness = Harness()
        harness.delivery.failuresRemaining = 2
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await settle(coordinator)
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await settle(coordinator)
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 2, "node")]))
        await settle(coordinator)

        #expect(harness.delivery.attempts.map(\.kind) == [.opened, .closed, .opened])
        #expect(harness.delivery.candidates.map(\.kind) == [.opened])
    }

    @Test func staleAndCorruptSnapshotsDoNotAlterBaselinesOrQueueDeliveries() async {
        let harness = Harness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        coordinator.observe(harness.snapshot(1, watched: [3000], [verified(3000, 1, "node")]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000), closed(3000)]))
        await settle(coordinator)
        #expect(harness.delivery.attempts.isEmpty)

        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 2, "node")]))
        await settle(coordinator)
        #expect(harness.delivery.candidates.map(\.kind) == [.opened])
    }


    private func settle(_ coordinator: PortChangeNotificationCoordinator) async {
        await coordinator.waitForDrainIdle()
    }
}

@MainActor
private final class Harness {
    let permission = PermissionSpy()
    let delivery = DeliverySpy()
    let clock = ClockSpy()
    let eligibility = EligibilitySpy()

    func coordinator(watched: Set<UInt16>) -> PortChangeNotificationCoordinator {
        PortChangeNotificationCoordinator(watchedPorts: watched, permission: permission, delivery: delivery, clock: clock, eligibility: eligibility)
    }

    func snapshot(_ generation: UInt64, epoch: UInt64 = 0, watched: Set<UInt16>, _ statuses: [PortStatus]) -> PortChangeNotificationSnapshot {
        PortChangeNotificationSnapshot(generation: generation, watchedEpoch: epoch, watchedPorts: watched, statuses: statuses)
    }
}

@MainActor
private final class PermissionSpy: PortChangeNotificationPermissionProviding {
    var status: PortChangeNotificationPermissionStatus = .authorized
    var requestResult: PortChangeNotificationPermissionStatus = .authorized
    var requestCount = 0
    var shouldThrow = false
    var requestGate: AsyncGate?
    var statusGate: AsyncGate?

    func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus {
        if let statusGate { await statusGate.wait() }
        return status
    }

    func requestNotificationPermission() async throws {
        requestCount += 1
        if let requestGate { await requestGate.wait() }
        if shouldThrow { throw TestError.failed }
        status = requestResult
    }
}

@MainActor
private final class DeliverySpy: PortChangeNotificationDelivering {
    var attempts: [PortChangeNotificationCandidate] = []
    var candidates: [PortChangeNotificationCandidate] = []
    var failNext = false
    var failuresRemaining = 0
    var gate: AsyncGate?

    func deliver(_ candidate: PortChangeNotificationCandidate) async throws {
        attempts.append(candidate)
        if failNext || failuresRemaining > 0 {
            failNext = false
            if failuresRemaining > 0 { failuresRemaining -= 1 }
            throw TestError.failed
        }
        if let gate { await gate.wait() }
        candidates.append(candidate)
    }
}

@MainActor
private final class ClockSpy: PortChangeNotificationClock {
    var time: TimeInterval = 0
    var monotonicTime: TimeInterval { time }
}

@MainActor
private final class EligibilitySpy: PortChangeNotificationEligibilityProviding {
    var notificationsEnabled = true
    var selectedNotificationPorts: Set<UInt16> = [3000, 3001]
    var notificationEligibilityRevision: UInt64 = 0
}

private enum TestError: Error { case failed }
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var waiterArrival: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            waiterArrival?.resume()
            waiterArrival = nil
        }
    }

    func waitForWaiter() async {
        guard waiters.isEmpty else { return }
        await withCheckedContinuation { continuation in
            waiterArrival = continuation
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private func closed(_ port: UInt16) -> PortStatus {
    PortStatus(port: port, isOpen: false, identityState: nil)
}

private func verified(_ port: UInt16, _ pid: Int, _ name: String) -> PortStatus {
    PortStatus(port: port, isOpen: true, identityState: .verified(VerifiedProcessIdentity(pid: pid, processName: name)!))
}

private func pidOnly(_ port: UInt16, _ pid: Int) -> PortStatus {
    PortStatus(port: port, isOpen: true, identityState: .unavailable(.processNameUnavailable(pid: pid)))
}

private func unreliable(_ port: UInt16) -> PortStatus {
    PortStatus(port: port, isOpen: true, identityState: .unavailable(.lookupFailed(message: "temporary")))
}
