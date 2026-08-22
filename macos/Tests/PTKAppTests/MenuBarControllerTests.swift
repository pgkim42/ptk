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

    @Test func newerGenerationPublishesBeforeStaleGenerationWithoutRegression() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        defer { controller.stop() }

        controller.performRefresh()
        controller.performRefresh()

        #expect(controller.newestRequestedGenerationForTesting == 2)
        #expect(controller.activeGenerationsForTesting == [1, 2])
        #expect(controller.pendingGenerationForTesting == nil)

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
    @Test func latestPendingRefreshReplacesEarlierPendingRefreshBeforeStarting() {
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        defer { controller.stop() }

        controller.performRefresh()
        controller.performRefresh()
        controller.performRefresh()
        controller.performRefresh()

        #expect(controller.newestRequestedGenerationForTesting == 4)
        #expect(controller.activeGenerationsForTesting == [1, 2])
        #expect(controller.pendingGenerationForTesting == 4)

        controller.settlePortForTesting(generation: 1, statuses: [])
        controller.settleServiceForTesting(generation: 1, snapshot: ServiceSnapshot(statuses: []))

        #expect(controller.activeGenerationsForTesting == [2, 4])
        #expect(controller.pendingGenerationForTesting == nil)

        controller.settlePortForTesting(generation: 2, statuses: [])
        controller.settleServiceForTesting(generation: 2, snapshot: ServiceSnapshot(statuses: []))
        controller.settlePortForTesting(generation: 4, statuses: [])
        controller.settleServiceForTesting(generation: 4, snapshot: ServiceSnapshot(statuses: []))

        #expect(!controller.viewModel.isRefreshing)
        #expect(controller.activeGenerationsForTesting.isEmpty)
    }

    @Test func stopClearsRefreshOwnershipAndPreventsLatePublication() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in [PortStatus(port: 3000, isOpen: true)] },
            serviceSnapshotWorker: { _ in
                ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Late", detail: "Late", state: .running)
                ])
            }
        )

        controller.performRefresh()
        controller.performRefresh()
        controller.performRefresh()

        #expect(controller.newestRequestedGenerationForTesting == 3)
        #expect(controller.activeGenerationsForTesting == [1, 2])
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
        #expect(controller.viewModel.statuses.isEmpty)
        #expect(controller.viewModel.serviceStatuses.isEmpty)
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

    @Test func killInProgressRejectsASecondConfirmationTarget() async {
        let gate = KillWorkerGate()
        let killCalls = LockedBox(0)
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
            killWorker: { _ in
                killCalls.withValue { $0 += 1 }
                gate.waitUntilOpened()
            }
        )
        defer {
            gate.open()
            controller.stop()
        }

        controller.viewModel.requestKill(KillTarget(port: 3000, pid: 100, processName: "node"))
        controller.viewModel.confirmKill()
        #expect(await eventually { killCalls.value == 1 && controller.viewModel.isTerminatingProcess })

        controller.viewModel.requestKill(KillTarget(port: 5173, pid: 200, processName: "vite"))

        #expect(controller.viewModel.killConfirmationTarget == nil)
        #expect(killCalls.value == 1)
        gate.open()
        #expect(await eventually { !controller.viewModel.isTerminatingProcess })
    }

    @Test func cancellingConfirmationDoesNotInvokeProductionKillWorker() {
        let killCalls = LockedBox(0)
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
            killWorker: { _ in killCalls.withValue { $0 += 1 } }
        )
        defer { controller.stop() }

        controller.viewModel.requestKill(KillTarget(port: 3000, pid: 100, processName: "node"))
        controller.viewModel.cancelKill()

        #expect(controller.viewModel.killConfirmationTarget == nil)
        #expect(!controller.viewModel.isTerminatingProcess)
        #expect(killCalls.value == 0)
    }

    @Test func settingsDraftChangesAreDiscardedWithoutSave() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        try settings.saveCustomPortProfile(title: "Original", expression: "3000")
        try settings.saveCustomServiceEndpoint(name: "Search", port: 19200)
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
        #expect(try reloaded.loadCustomServiceEndpoints().map(\.name) == ["Search"])
    }

    @Test func customServiceAdditionRejectsBuiltInDatabasePort() {
        let viewModel = makeViewModel(settings: AppSettings(store: InMemorySettingsStore()))

        #expect(throws: AppSettingsError.builtInServicePort(5432)) {
            try viewModel.addingCustomServiceEndpoint(
                name: "Local PostgreSQL",
                portText: "5432",
                to: []
            )
        }
    }

    @Test func settingsSaveReportsBuiltInPortAsCustomServiceError() {
        let viewModel = makeViewModel(settings: AppSettings(store: InMemorySettingsStore()))
        var draft = viewModel.makeSettingsDraft()
        draft.customServiceEndpoints = [DatabaseEndpoint(name: "Local PostgreSQL", port: 5432)]

        do {
            try viewModel.saveSettingsDraft(draft)
            Issue.record("Built-in service port must be rejected.")
        } catch let SettingsDraftSaveError.customServices(error) {
            #expect(error as? AppSettingsError == .builtInServicePort(5432))
        } catch {
            Issue.record("Built-in service port used the wrong settings error.")
        }
    }

    @Test func settingsSavePublishesNormalizedExpression() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        let viewModel = makeViewModel(settings: settings)
        let preset = AppDefaults.portPresets[0]
        var draft = viewModel.makeSettingsDraft()
        draft.portExpression = "  \(preset.expression)  "

        try viewModel.saveSettingsDraft(draft)

        #expect(settings.watchedPortsExpression == preset.expression)
        #expect(viewModel.portExpression == preset.expression)
        #expect(viewModel.currentProfileTitle == preset.title)
    }

    @MainActor
    @Test func copyActionsShowFeedbackAndClearItAfterDelay() async {
        var copied: [String] = []
        let viewModel = PortMonitorViewModel(
            settings: AppSettings(store: InMemorySettingsStore()),
            onRefresh: {},
            onCopyText: { copied.append($0) },
            copyFeedbackDurationNanoseconds: 20_000_000
        )
        let status = PortStatus(port: 3000, isOpen: true, pid: 42, processName: "node")
        let dockerRow = DockerContainerPortRow(
            id: "api",
            name: "api",
            detail: "3000 -> 3000",
            copyCandidates: [
                DockerPortCopyCandidate(label: "3000", urlString: "http://localhost:3000")
            ]
        )
        viewModel.statuses = [status]

        viewModel.copyLocalhostURL(for: status)
        viewModel.copyPortDetails(for: status)
        viewModel.copyDockerContainerURL(for: dockerRow)
        viewModel.copyOpenPortsSummary()

        #expect(copied.count == 4)
        #expect(viewModel.copyFeedbackMessage == "복사됨")

        #expect(await eventually { viewModel.copyFeedbackMessage == nil })
    }

}

@MainActor private func makeViewModel(settings: AppSettings) -> PortMonitorViewModel {
    PortMonitorViewModel(
        settings: settings,
        parser: PortRangeParser(),
        onRefresh: {},
        onSettingsRefresh: {},
        onKill: { _ in .invalidated },
        onKillSettled: {},
        onIntervalChange: { _ in },
        onOpenLocalhost: { _ in },
        onCopyText: { _ in }
    )
}

@MainActor private func eventually(
    timeout: TimeInterval = 2,
    _ predicate: @MainActor () -> Bool
) async -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    repeat {
        if predicate() {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    } while ProcessInfo.processInfo.systemUptime < deadline
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

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storedValue)
        lock.unlock()
    }
}

private final class KillWorkerGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false

    func waitUntilOpened() {
        condition.lock()
        while !isOpen {
            condition.wait()
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
