import Foundation
import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
@Suite(.serialized) struct PortChangeNotificationIntegrationTests {
    @Test func enabledSaveCommitsWatchedPortsBeforeItsSinglePermissionRequest() async throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let permissionSignal = PermissionRequestSignal()
        var events: [String] = []
        var permissionRequests = 0
        let viewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onWatchedPortsCommitted: { old, new in
                #expect(old == [3000])
                #expect(new == [5173])
                events.append("commit")
            },
            onPermissionRequest: {
                permissionRequests += 1
                events.append("permission")
                await permissionSignal.record()
                return .authorized
            }
        )

        var draft = viewModel.makeSettingsDraft()
        draft.portExpression = "5173"
        draft.portChangeNotificationPreference = .init(isEnabled: true, portsExpression: nil)
        try viewModel.saveSettingsDraft(draft)
        await permissionSignal.wait()
        #expect(await eventually { viewModel.notificationPermissionStatus == .authorized })

        #expect(events == ["commit", "permission"])
        #expect(permissionRequests == 1)
        #expect(try settings.loadPortChangeNotificationPreference() == .init(isEnabled: true, portsExpression: "5173"))
    }

    @Test func watchedPortCommitUsesSemanticSetsForEquivalentExpressions() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000-3001"
        var committedPorts: [(Set<UInt16>, Set<UInt16>)] = []
        var refreshes = 0
        let viewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onSettingsRefresh: { refreshes += 1 },
            onWatchedPortsCommitted: { old, new in committedPorts.append((old, new)) }
        )

        try viewModel.saveExpression("3001,3000")

        #expect(committedPorts.count == 1)
        #expect(committedPorts.first?.0 == Set([3000, 3001]))
        #expect(committedPorts.first?.1 == Set([3000, 3001]))
        #expect(refreshes == 1)
        #expect(settings.watchedPortsExpression == "3001,3000")
    }
    @Test func cancellingAChangedSettingsSheetDraftDoesNotPersistOrRequestPermission() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        var commits = 0
        var permissionRequests = 0
        var dismissals = 0
        let viewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onWatchedPortsCommitted: { _, _ in commits += 1 },
            onPermissionRequest: {
                permissionRequests += 1
                return .authorized
            }
        )
        let actions = SettingsSheetActions(viewModel: viewModel) {
            dismissals += 1
        }
        var changedDraft = viewModel.makeSettingsDraft()
        changedDraft.portChangeNotificationPreference = .init(isEnabled: true, portsExpression: "5173")

        actions.cancel()

        #expect(dismissals == 1)
        #expect(viewModel.portChangeNotificationPreference == .init(isEnabled: false, portsExpression: nil))
        #expect(try settings.loadPortChangeNotificationPreference() == .init(isEnabled: false, portsExpression: nil))
        #expect(commits == 0)
        #expect(permissionRequests == 0)
    }
    @Test func invalidSettingsSheetSaveRetainsTheChangedDraftAndHasNoNotificationSideEffects() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        var commits = 0
        var refreshes = 0
        var intervalChanges = 0
        var permissionRequests = 0
        var dismissals = 0
        let viewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onSettingsRefresh: { refreshes += 1 },
            onIntervalChange: { _ in intervalChanges += 1 },
            onWatchedPortsCommitted: { _, _ in commits += 1 },
            onPermissionRequest: {
                permissionRequests += 1
                return .authorized
            }
        )
        let actions = SettingsSheetActions(viewModel: viewModel) {
            dismissals += 1
        }
        var invalidDraft = viewModel.makeSettingsDraft()
        invalidDraft.portExpression = "not-a-port"
        invalidDraft.portChangeNotificationPreference = .init(isEnabled: true, portsExpression: "5173")

        #expect(throws: SettingsDraftSaveError.self) {
            try actions.save(invalidDraft)
        }

        #expect(dismissals == 0)
        #expect(viewModel.makeSettingsDraft() != invalidDraft)
        #expect(settings.watchedPortsExpression == "3000")
        #expect(try settings.loadPortChangeNotificationPreference() == .init(isEnabled: false, portsExpression: nil))
        #expect(commits == 0)
        #expect(refreshes == 0)
        #expect(intervalChanges == 0)
        #expect(permissionRequests == 0)
    }

    @Test func disabledSaveDoesNotPromptAndPermissionReadRemainsPassive() async throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        var permissionReads = 0
        var permissionRequests = 0
        let viewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onPermissionRefresh: {
                permissionReads += 1
                return .denied
            },
            onPermissionRequest: {
                permissionRequests += 1
                return .authorized
            }
        )
        var draft = viewModel.makeSettingsDraft()
        draft.portChangeNotificationPreference = .init(isEnabled: false, portsExpression: nil)

        try viewModel.saveSettingsDraft(draft)
        await viewModel.refreshNotificationPermissionStatus()

        #expect(permissionReads == 1)
        #expect(permissionRequests == 0)
        #expect(viewModel.notificationPermissionStatus == .denied)
    }

    @Test func repeatedSettingsPresentationRefreshesPermissionPassivelyAndCancellationKeepsCommittedState() async throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        let refreshSignal = PermissionRequestSignal()
        var permissionRequests = 0
        var permissionReads = 0
        var dismissals = 0
        let viewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onPermissionRefresh: {
                permissionReads += 1
                await refreshSignal.record()
                return .denied
            },
            onPermissionRequest: {
                permissionRequests += 1
                return .authorized
            }
        )
        let actions = SettingsSheetActions(viewModel: viewModel) {
            dismissals += 1
            viewModel.isShowingSettings = false
        }
        let committedDraft = viewModel.makeSettingsDraft()

        viewModel.isShowingSettings = true
        await refreshSignal.wait(for: 1)
        actions.cancel()
        viewModel.isShowingSettings = true
        await refreshSignal.wait(for: 2)
        actions.cancel()

        #expect(permissionReads == 2)
        #expect(dismissals == 2)
        #expect(viewModel.isShowingSettings == false)
        #expect(viewModel.makeSettingsDraft() == committedDraft)
        #expect(try settings.loadPortChangeNotificationPreference() == .init(isEnabled: false, portsExpression: nil))
        #expect(permissionRequests == 0)
    }

    @Test func coldAndWarmNotificationClicksReachOnlyTheControllerPanelSeam() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let router = PortChangeNotificationResponseRouter()
        let responseHandler = NotificationResponseHandler(router: router)
        var panelPresentations = 0
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
            notificationResponseHandler: responseHandler,
            notificationPanelPresentationForTesting: {
                panelPresentations += 1
            }
        )
        defer { controller.stop() }

        responseHandler.routeDefaultAction()
        #expect(panelPresentations == 0)

        controller.start()
        #expect(panelPresentations == 1)

        responseHandler.routeDefaultAction()
        #expect(panelPresentations == 2)
        #expect(controller.lastRefreshTriggerForTesting == .startup)
        #expect(controller.viewModel.statuses.isEmpty)
        #expect(controller.viewModel.recentPortChanges.isEmpty)

        controller.stop()
        responseHandler.routeDefaultAction()
        #expect(panelPresentations == 2)
    }

    @Test func acceptedRefreshesKeepHistoryIndependentAndStaleSettlementCannotRegressThem() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let workers = BlockingWorkers(expectedWorkers: 4)
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                workers.wait()
                return []
            },
            serviceSnapshotWorker: { _ in
                workers.wait()
                return ServiceSnapshot(statuses: [])
            }
        )
        defer {
            controller.stop()
            workers.open(count: 4)
        }

        controller.performRefresh()
        #expect(await eventually { controller.activeGenerationsForTesting == [1] })
        controller.settlePortForTesting(generation: 1, statuses: [PortStatus(port: 3000, isOpen: false)])
        controller.settleServiceForTesting(generation: 1, snapshot: ServiceSnapshot(statuses: []))

        controller.performRefresh()
        #expect(await eventually { controller.activeGenerationsForTesting == [2] })
        controller.settlePortForTesting(generation: 2, statuses: [
            PortStatus(port: 3000, isOpen: true, pid: 41, processName: "server")
        ])
        controller.settleServiceForTesting(generation: 2, snapshot: ServiceSnapshot(statuses: []))

        let acceptedStatuses = controller.viewModel.statuses
        let acceptedHistory = controller.viewModel.recentPortChanges
        #expect(acceptedHistory.map(\.kind) == [.opened])

        controller.settlePortForTesting(
            generation: 1,
            statuses: [PortStatus(port: 4000, isOpen: true, pid: 99, processName: "stale")]
        )
        controller.settleServiceForTesting(
            generation: 1,
            snapshot: ServiceSnapshot(statuses: [ServiceStatus(name: "Stale", detail: "old", state: .stopped)])
        )

        #expect(controller.viewModel.statuses == acceptedStatuses)
        #expect(controller.viewModel.recentPortChanges == acceptedHistory)
    }

    @Test func stopRejectsLateRefreshWorkAfterBothWorkersAndControllerSettlementsReturn() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let workers = BlockingWorkers()
        let settlementSignal = PermissionRequestSignal()
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                workers.wait()
                workers.recordReturn()
                return [PortStatus(port: 3000, isOpen: true, pid: 41, processName: "late")]
            },
            serviceSnapshotWorker: { _ in
                workers.wait()
                workers.recordReturn()
                return ServiceSnapshot(statuses: [ServiceStatus(name: "Late", detail: "late", state: .running)])
            },
            refreshWorkSettlementForTesting: {
                Task { await settlementSignal.record() }
            }
        )

        controller.performRefresh()
        #expect(await eventually { controller.activeGenerationsForTesting == [1] })
        await workers.waitForStarts()
        controller.stop()
        workers.open(count: 2)
        await workers.waitForReturns()
        await settlementSignal.wait(for: 2)

        #expect(controller.viewModel.statuses.isEmpty)
        #expect(controller.viewModel.serviceStatuses.isEmpty)
        #expect(controller.viewModel.recentPortChanges.isEmpty)
        #expect(controller.viewModel.isRefreshing == false)
    }

    @Test func notificationSettingsUsesLiteralPreferredRouteAndPreservesPreferenceAcrossFallbackFailures() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        let savedPreference = PortChangeNotificationPreference(isEnabled: true, portsExpression: "5173")
        try settings.replaceSettings(
            watchedPortsExpression: settings.watchedPortsExpression,
            refreshInterval: settings.refreshInterval,
            theme: settings.theme,
            profiles: settings.customPortProfiles,
            serviceEndpoints: settings.customServiceEndpoints,
            portChangeNotificationPreference: savedPreference
        )
        var preferredURLs: [URL] = []
        let preferredViewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onOpenNotificationSettings: { url in
                preferredURLs.append(url)
                return true
            }
        )

        preferredViewModel.openNotificationSettings()

        #expect(preferredURLs.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=dev.pgkim.ptk"
        ])
        #expect(preferredViewModel.notificationPermissionError == nil)
        #expect(try settings.loadPortChangeNotificationPreference() == savedPreference)

        var fallbackURLs: [URL] = []
        let fallbackViewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onOpenNotificationSettings: { url in
                fallbackURLs.append(url)
                return fallbackURLs.count == 2
            }
        )

        fallbackViewModel.openNotificationSettings()

        #expect(fallbackURLs.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=dev.pgkim.ptk",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ])
        #expect(fallbackViewModel.notificationPermissionError == nil)
        #expect(try settings.loadPortChangeNotificationPreference() == savedPreference)

        var failedURLs: [URL] = []
        let failingViewModel = PortMonitorViewModel(
            settings: settings,
            onRefresh: {},
            onOpenNotificationSettings: { url in
                failedURLs.append(url)
                return false
            }
        )
        failingViewModel.openNotificationSettings()

        #expect(failedURLs.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=dev.pgkim.ptk",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ])
        #expect(failingViewModel.notificationPermissionError == "알림 설정을 열 수 없습니다.")
        #expect(try settings.loadPortChangeNotificationPreference() == savedPreference)
    }
}
private actor PermissionRequestSignal {
    private var recordings = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        recordings += 1
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func wait(for count: Int = 1) async {
        while recordings < count {
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}

@MainActor
private final class NotificationResponseHandler: PortChangeNotificationResponseHandling {
    private let router: PortChangeNotificationResponseRouter

    init(router: PortChangeNotificationResponseRouter) {
        self.router = router
    }

    func attachPanelHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        router.attachPanelHandler(handler)
    }

    func detachPanelHandler() {
        router.detachPanelHandler()
    }

    func routeDefaultAction() {
        router.routeDefaultAction()
    }
}

private final class BlockingWorkers: @unchecked Sendable {
    private let condition = NSCondition()
    private let starts = DispatchGroup()
    private let returns = DispatchGroup()
    private var openings = 0

    init(expectedWorkers: Int = 2) {
        for _ in 0..<expectedWorkers {
            starts.enter()
            returns.enter()
        }
    }

    func wait() {
        starts.leave()
        condition.lock()
        while openings == 0 {
            condition.wait()
        }
        openings -= 1
        condition.unlock()
    }

    func recordReturn() {
        returns.leave()
    }

    func waitForStarts() async {
        await wait(for: starts)
    }

    func waitForReturns() async {
        await wait(for: returns)
    }

    private func wait(for group: DispatchGroup) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                group.wait()
                continuation.resume()
            }
        }
    }

    func open(count: Int) {
        condition.lock()
        openings += count
        condition.broadcast()
        condition.unlock()
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(1),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if condition() { return true }
        try? await clock.sleep(for: pollInterval)
    }

    return condition()
}
