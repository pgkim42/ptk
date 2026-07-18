import Foundation
import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
struct PortChangeNotificationCoordinatorTests {
    @Test func reliableOpenAndCloseTransitionsAreDelivered() async {
        let harness = NotificationHarness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        coordinator.observe(harness.snapshot(0, watched: [3000], [unreliable(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 10, "node")]))
        await coordinator.waitForDrainIdle()

        coordinator.accept(harness.snapshot(1, watched: [3000], [verified(3000, 10, "node")]))
        coordinator.observe(harness.snapshot(1, watched: [3000], [closed(3000)]))
        await coordinator.waitForDrainIdle()

        #expect(harness.delivery.candidates.map(\.kind) == [.opened, .closed])
    }

    @Test func watchChangeInvalidatesQueuedStateAndReaddStartsFromBaseline() async {
        let harness = NotificationHarness()
        harness.permission.status = .notDetermined
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))

        coordinator.commitWatchedPorts([])
        coordinator.commitWatchedPorts([3000])
        coordinator.accept(
            harness.snapshot(
                1,
                epoch: coordinator.watchedEpoch,
                watched: [3000],
                [verified(3000, 1, "node")]
            )
        )
        await coordinator.waitForDrainIdle()

        #expect(harness.delivery.candidates.isEmpty)
    }

    @Test func staleCorruptAndIdentityOnlySnapshotsDoNotDuplicateDelivery() async {
        let harness = NotificationHarness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        coordinator.observe(harness.snapshot(1, watched: [3000], [verified(3000, 1, "stale")]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000), closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 2, "node")]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 3, "changed")]))
        await coordinator.waitForDrainIdle()

        #expect(harness.delivery.candidates.map(\.kind) == [.opened])
    }

    @Test func deliveryPreservesPortOrderAndContinuesAfterFailure() async {
        let harness = NotificationHarness()
        harness.delivery.failuresRemaining = 1
        let coordinator = harness.coordinator(watched: [3000, 3001])
        coordinator.accept(
            harness.snapshot(0, watched: [3000, 3001], [closed(3000), closed(3001)])
        )
        coordinator.observe(
            harness.snapshot(
                0,
                watched: [3000, 3001],
                [verified(3000, 1, "a"), verified(3001, 2, "b")]
            )
        )
        await coordinator.waitForDrainIdle()

        #expect(harness.delivery.attempts.map(\.port) == [3000, 3001])
        #expect(harness.delivery.candidates.map(\.port) == [3001])
    }

    @Test func permissionStateControlsDeliveryWithoutChangingPreference() async {
        let harness = NotificationHarness()
        harness.permission.status = .denied
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))

        await coordinator.refreshPermissionStatus()
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await coordinator.waitForDrainIdle()
        #expect(harness.delivery.attempts.isEmpty)
        #expect(harness.eligibility.notificationsEnabled)

        harness.permission.status = .authorized
        await coordinator.refreshPermissionStatus()
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await coordinator.waitForDrainIdle()
        #expect(harness.delivery.candidates.map(\.kind) == [.closed])
    }

    @Test func permissionRequestPublishesSuccessAndFailure() async {
        let harness = NotificationHarness()
        harness.permission.status = .notDetermined
        let coordinator = harness.coordinator(watched: [3000])

        await coordinator.requestPermissionIfNeeded()
        #expect(harness.permission.requestCount == 1)
        #expect(coordinator.permissionStatus == .authorized)

        harness.permission.status = .notDetermined
        harness.permission.shouldThrow = true
        await coordinator.requestPermissionIfNeeded()
        #expect(coordinator.lastPermissionRequestError != nil)
    }

    @Test func oppositeDirectionIsNotSuppressed() async {
        let harness = NotificationHarness()
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await coordinator.waitForDrainIdle()

        harness.clock.time = 1
        coordinator.observe(harness.snapshot(0, watched: [3000], [closed(3000)]))
        await coordinator.waitForDrainIdle()

        #expect(harness.delivery.candidates.map(\.kind) == [.opened, .closed])
    }

    @Test func stopBlocksPermissionRequestsAndDelivery() async {
        let harness = NotificationHarness()
        harness.permission.status = .notDetermined
        let coordinator = harness.coordinator(watched: [3000])
        coordinator.accept(harness.snapshot(0, watched: [3000], [closed(3000)]))
        coordinator.stop()

        await coordinator.requestPermissionIfNeeded()
        coordinator.observe(harness.snapshot(0, watched: [3000], [verified(3000, 1, "node")]))
        await coordinator.waitForDrainIdle()

        #expect(harness.permission.requestCount == 0)
        #expect(harness.delivery.attempts.isEmpty)
    }
}

@MainActor
private final class NotificationHarness {
    let permission = NotificationPermissionSpy()
    let delivery = NotificationDeliverySpy()
    let clock = NotificationClockSpy()
    let eligibility = NotificationEligibilitySpy()

    func coordinator(watched: Set<UInt16>) -> PortChangeNotificationCoordinator {
        PortChangeNotificationCoordinator(
            watchedPorts: watched,
            permission: permission,
            delivery: delivery,
            clock: clock,
            eligibility: eligibility
        )
    }

    func snapshot(
        _ generation: UInt64,
        epoch: UInt64 = 0,
        watched: Set<UInt16>,
        _ statuses: [PortStatus]
    ) -> PortChangeNotificationSnapshot {
        PortChangeNotificationSnapshot(
            generation: generation,
            watchedEpoch: epoch,
            watchedPorts: watched,
            statuses: statuses
        )
    }
}

@MainActor
private final class NotificationPermissionSpy: PortChangeNotificationPermissionProviding {
    var status: PortChangeNotificationPermissionStatus = .authorized
    var requestCount = 0
    var shouldThrow = false

    func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus { status }

    func requestNotificationPermission() async throws {
        requestCount += 1
        if shouldThrow { throw NotificationTestError.failed }
        status = .authorized
    }
}

@MainActor
private final class NotificationDeliverySpy: PortChangeNotificationDelivering {
    var attempts: [PortChangeNotificationCandidate] = []
    var candidates: [PortChangeNotificationCandidate] = []
    var failuresRemaining = 0

    func deliver(_ candidate: PortChangeNotificationCandidate) async throws {
        attempts.append(candidate)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw NotificationTestError.failed
        }
        candidates.append(candidate)
    }
}

@MainActor
private final class NotificationClockSpy: PortChangeNotificationClock {
    var time: TimeInterval = 0
    var monotonicTime: TimeInterval { time }
}

@MainActor
private final class NotificationEligibilitySpy: PortChangeNotificationEligibilityProviding {
    var notificationsEnabled = true
    var selectedNotificationPorts: Set<UInt16> = [3000, 3001]
    var notificationEligibilityRevision: UInt64 = 0
}

private enum NotificationTestError: Error { case failed }

private func closed(_ port: UInt16) -> PortStatus {
    PortStatus(port: port, isOpen: false, identityState: nil)
}

private func verified(_ port: UInt16, _ pid: Int, _ name: String) -> PortStatus {
    PortStatus(
        port: port,
        isOpen: true,
        identityState: .verified(VerifiedProcessIdentity(pid: pid, processName: name)!)
    )
}

private func unreliable(_ port: UInt16) -> PortStatus {
    PortStatus(
        port: port,
        isOpen: true,
        identityState: .unavailable(.lookupFailed(message: "temporary"))
    )
}
