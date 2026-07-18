import Foundation
import AppKit
import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
@Suite(.serialized) struct MenuBarControllerTests {
    @Test func refreshRunsPortAndServiceWorkersAndPublishesAsynchronously() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000,3001"
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { ports in
                ports.map { PortStatus(port: $0, isOpen: true) }
            },
            serviceSnapshotWorker: { _ in
                ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Docker", detail: "Daemon", state: .running)
                ])
            }
        )

        controller.performRefresh()

        #expect(controller.viewModel.isRefreshing)
        #expect(await eventually {
            !controller.viewModel.isRefreshing
        })
        #expect(controller.viewModel.openPorts.map(\.port) == [3000, 3001])
        #expect(controller.viewModel.serviceStatuses.map(\.name) == ["Docker"])
    }

    @Test func newerGenerationPublishesBeforeStaleGenerationWithoutRegression() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let portGate = BlockingGate()
        let serviceGate = BlockingGate()
        let portCalls = LockedBox(0)
        let serviceCalls = LockedBox(0)
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                portCalls.withValue { $0 += 1 }
                portGate.waitUpToOneSecond()
                return []
            },
            serviceSnapshotWorker: { _ in
                serviceCalls.withValue { $0 += 1 }
                serviceGate.waitUpToOneSecond()
                return ServiceSnapshot(statuses: [])
            }
        )
        defer {
            controller.stop()
            portGate.open()
            serviceGate.open()
        }

        controller.performRefresh()
        controller.performRefresh()
        #expect(await eventually { portCalls.value == 2 && serviceCalls.value == 2 })

        let newestPortStatuses = [
            PortStatus(port: 4000, isOpen: true, pid: 400, processName: "new")
        ]
        let newestServiceStatuses = [
            ServiceStatus(name: "Newest", detail: "Current", state: .running)
        ]
        let newestDockerRows = [
            DockerContainerPortRow(id: "new", name: "new", detail: "4000 -> 4000")
        ]
        controller.settlePortForTesting(generation: 2, statuses: newestPortStatuses)
        #expect(controller.viewModel.isRefreshing)
        controller.settleServiceForTesting(
            generation: 2,
            snapshot: ServiceSnapshot(
                statuses: newestServiceStatuses,
                dockerContainerRows: newestDockerRows
            )
        )

        #expect(!controller.viewModel.isRefreshing)
        #expect(controller.activeGenerationsForTesting == [1])
        let acceptedStatuses = controller.viewModel.statuses
        let acceptedError = controller.viewModel.errorMessage
        let acceptedHistory = controller.viewModel.recentPortChanges
        let acceptedMenuContent = controller.viewModel.menuBarStatusContent
        let acceptedServiceStatuses = controller.viewModel.serviceStatuses
        let acceptedDockerRows = controller.viewModel.dockerContainerRows

        controller.settlePortForTesting(
            generation: 1,
            statuses: [
                PortStatus(
                    port: 3000,
                    isOpen: true,
                    pid: 300,
                    processName: "stale",
                    message: "stale port error"
                )
            ]
        )
        controller.settleServiceForTesting(
            generation: 1,
            snapshot: ServiceSnapshot(
                statuses: [
                    ServiceStatus(name: "Stale", detail: "Old", state: .stopped)
                ],
                dockerContainerRows: [
                    DockerContainerPortRow(id: "old", name: "old", detail: "3000 -> 3000")
                ]
            )
        )
        controller.settlePortErrorForTesting(
            generation: 1,
            errorMessage: "duplicate stale port error"
        )
        controller.settleServiceErrorForTesting(
            generation: 1,
            errorMessage: "duplicate stale service error"
        )

        #expect(!controller.viewModel.isRefreshing)
        #expect(controller.activeGenerationsForTesting.isEmpty)
        #expect(controller.viewModel.statuses == acceptedStatuses)
        #expect(controller.viewModel.errorMessage == acceptedError)
        #expect(controller.viewModel.recentPortChanges == acceptedHistory)
        #expect(controller.viewModel.menuBarStatusContent == acceptedMenuContent)
        #expect(controller.viewModel.serviceStatuses == acceptedServiceStatuses)
        #expect(controller.viewModel.dockerContainerRows == acceptedDockerRows)
    }

    @Test func stopCancelsOwnedWorkAndPreventsLatePublication() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let portGate = BlockingGate()
        let serviceGate = BlockingGate()
        let portCalls = LockedBox(0)
        let serviceCalls = LockedBox(0)
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                portCalls.withValue { $0 += 1 }
                portGate.waitUpToOneSecond()
                return [PortStatus(port: 3000, isOpen: true)]
            },
            serviceSnapshotWorker: { _ in
                serviceCalls.withValue { $0 += 1 }
                serviceGate.waitUpToOneSecond()
                return ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Late", detail: "Late", state: .running)
                ])
            }
        )

        controller.performRefresh()
        controller.performRefresh()
        controller.performRefresh()
        #expect(await eventually { portCalls.value == 2 && serviceCalls.value == 2 })
        #expect(controller.pendingGenerationForTesting == 3)

        controller.stop()
        #expect(!controller.viewModel.isRefreshing)
        #expect(controller.newestRequestedGenerationForTesting == nil)
        #expect(controller.activeGenerationsForTesting.isEmpty)
        #expect(controller.pendingGenerationForTesting == nil)

        controller.settlePortForTesting(
            generation: 1,
            statuses: [PortStatus(port: 3000, isOpen: true)]
        )
        controller.settleServiceForTesting(
            generation: 1,
            snapshot: ServiceSnapshot(statuses: [
                ServiceStatus(name: "Late", detail: "Late", state: .running)
            ])
        )
        portGate.open()
        serviceGate.open()
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(controller.viewModel.statuses.isEmpty)
        #expect(controller.viewModel.serviceStatuses.isEmpty)
        #expect(portCalls.value == 2)
        #expect(serviceCalls.value == 2)
        controller.performRefresh()
        #expect(controller.viewModel.statuses.isEmpty)
    }

    @Test func killSuccessAndFailureEachTriggerExactlyOneKillRefresh() async {
        for failureMessage in [String?.none, "denied"] {
            let refreshCalls = LockedBox(0)
            let controller = MenuBarController(
                settings: AppSettings(store: InMemorySettingsStore()),
                portScanWorker: { _ in
                    refreshCalls.withValue { $0 += 1 }
                    return []
                },
                serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
                killWorker: { _ in
                    if let failureMessage {
                        throw TestFailure(failureMessage)
                    }
                }
            )
            controller.viewModel.requestKill(KillTarget(port: 3000, pid: 100, processName: "node"))
            controller.viewModel.confirmKill()

            #expect(await eventually { !controller.viewModel.isTerminatingProcess })
            #expect(await eventually { controller.lastRefreshTriggerForTesting == .kill })
            #expect(await eventually { !controller.viewModel.isRefreshing })
            #expect(refreshCalls.value == 1)
            #expect(controller.lastRefreshTriggerForTesting == .kill)
            #expect(controller.viewModel.killErrorMessage == failureMessage)
        }
    }

    @Test func settingsDraftChangesAreDiscardedWithoutSave() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        try settings.saveCustomPortProfile(title: "Original", expression: "3000")
        try settings.saveCustomServiceEndpoint(name: "Redis", port: 6379)
        settings.theme = .system
        let viewModel = makeViewModel(settings: settings)

        var draft = viewModel.makeSettingsDraft()
        draft.theme = .dark
        draft.customPortProfiles = try viewModel.addingCustomProfile(
            title: "Temporary",
            expression: "5173",
            to: draft.customPortProfiles
        )
        draft.customPortProfiles.removeAll { $0.title == "Original" }
        draft.customServiceEndpoints.removeAll()

        let reloaded = AppSettings(store: store)
        #expect(reloaded.theme == .system)
        #expect(try reloaded.loadCustomPortProfiles().map(\.title) == ["Original"])
        #expect(try reloaded.loadCustomServiceEndpoints().map(\.name) == ["Redis"])
    }

}

@MainActor private func makeViewModel(
    settings: AppSettings = AppSettings(store: InMemorySettingsStore()),
    onRefresh: @escaping () -> Void = {},
    onSettingsRefresh: (() -> Void)? = nil,
    onKill: @escaping @MainActor (KillTarget) async -> KillRequestResult = { _ in .invalidated },
    onKillSettled: @escaping () -> Void = {},
    onIntervalChange: @escaping (RefreshInterval) -> Void = { _ in },
    onOpenLocalhost: @escaping (URL) -> Void = { _ in },
    onCopyText: @escaping (String) -> Void = { _ in }
) -> PortMonitorViewModel {
    PortMonitorViewModel(
        settings: settings,
        parser: PortRangeParser(),
        onRefresh: onRefresh,
        onSettingsRefresh: onSettingsRefresh ?? onRefresh,
        onKill: onKill,
        onKillSettled: onKillSettled,
        onIntervalChange: onIntervalChange,
        onOpenLocalhost: onOpenLocalhost,
        onCopyText: onCopyText
    )
}

@MainActor private func eventually(
    attempts: Int = 1_000,
    _ predicate: @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if predicate() {
            return true
        }
        await Task.yield()
    }
    return predicate()
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storedValue)
        lock.unlock()
    }
}

private final class BlockingGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false
    private var waiterPresent = false

    var hasWaiter: Bool {
        condition.lock()
        defer { condition.unlock() }
        return waiterPresent
    }

    func waitUpToOneSecond() {
        condition.lock()
        waiterPresent = true
        let deadline = Date(timeIntervalSinceNow: 1)
        while !isOpen, condition.wait(until: deadline) {
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}

private struct TestFailure: Error, CustomStringConvertible, Sendable {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
