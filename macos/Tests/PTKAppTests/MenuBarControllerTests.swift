import Foundation
import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
@Suite(.serialized) struct MenuBarControllerTests {
    @Test func refreshStartsServiceStatusLoadWithoutWaitingForCompletion() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        var serviceCompletions: [@MainActor ([ServiceStatus]) -> Void] = []
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: FakeSocketConnector(openPorts: []),
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceStatusLoader: { completion in
                serviceCompletions.append(completion)
            }
        )

        controller.performRefresh()

        #expect(serviceCompletions.count == 1)
    }

    @Test func refreshStillLoadsServiceStatusesWhenWatchedPortsAreInvalid() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "nope"
        var serviceLoadCount = 0
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in
                serviceLoadCount += 1
                completion([ServiceStatus(name: "Docker", detail: "Daemon", state: .running)])
            }
        )

        controller.performRefresh()

        #expect(serviceLoadCount == 1)
    }

    @Test func refreshUpdatesViewModelTitle() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000,3001"
        var serviceCompletions: [@MainActor ([ServiceStatus]) -> Void] = []
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: FakeSocketConnector(openPorts: [3000, 3001]),
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceStatusLoader: { completion in
                serviceCompletions.append(completion)
            }
        )

        controller.performRefresh()

        #expect(controller.viewModel.statuses.count == 2)
        #expect(controller.viewModel.openPorts.count == 2)
        #expect(controller.viewModel.openPorts.allSatisfy { $0.isOpen })
    }

    @Test func refreshRecordsRecentPortChangesAfterInitialBaseline() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000,3001"
        let connector = MutableFakeSocketConnector(openPorts: [])
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: connector,
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceStatusLoader: { _ in }
        )

        controller.performRefresh()
        #expect(controller.viewModel.recentPortChanges.isEmpty)

        connector.openPorts = [3000]
        controller.performRefresh()
        #expect(controller.viewModel.recentPortChanges.map(\.kind) == [.opened])
        #expect(controller.viewModel.recentPortChanges.map(\.port) == [3000])

        connector.openPorts = []
        controller.performRefresh()
        #expect(controller.viewModel.recentPortChanges.map(\.kind).prefix(2) == [.closed, .opened])
        #expect(controller.viewModel.recentPortChanges.map(\.port).prefix(2) == [3000, 3000])
    }

    @Test func refreshSetsErrorOnBadExpression() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "invalid-!!!"
        var serviceLoadCount = 0
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in
                serviceLoadCount += 1
                completion([])
            }
        )

        controller.performRefresh()

        #expect(controller.viewModel.hasError)
        #expect(controller.viewModel.openPorts.isEmpty)
    }

    @Test func startCanShowPanelImmediatelyForAutomation() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in
                completion([])
            }
        )
        defer { controller.stop() }

        controller.start(showPanelOnLaunch: true)

        #expect(controller.isPanelVisible)
    }

    @Test func panelClosedUsesQuietCadenceSlowerThanAllUserIntervals() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.refreshInterval = .tenSeconds
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in completion([]) }
        )
        defer { controller.stop() }

        controller.start(showPanelOnLaunch: true)
        controller.applyPanelClosedForTesting()

        #expect(MenuBarController.quietRefreshCadence > RefreshInterval.allCases.map(\.rawValue).max()!)
        #expect(controller.activeRefreshCadenceSeconds == MenuBarController.quietRefreshCadence)
        #expect((controller.currentRefreshTimerInterval ?? 0) > RefreshInterval.tenSeconds.rawValue)
    }

    @Test func panelReopenRestoresNormalTenSecondCadenceAndRefreshes() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.refreshInterval = .tenSeconds
        var refreshCount = 0
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: FakeSocketConnector(openPorts: []),
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceStatusLoader: { completion in
                refreshCount += 1
                completion([])
            }
        )
        defer { controller.stop() }

        controller.start(showPanelOnLaunch: true)
        controller.applyPanelClosedForTesting()
        let closedRefreshCount = refreshCount
        controller.applyPanelOpenedForTesting()

        #expect(controller.activeRefreshCadenceSeconds == RefreshInterval.tenSeconds.rawValue)
        #expect(controller.currentRefreshTimerInterval == RefreshInterval.tenSeconds.rawValue)
        #expect(refreshCount > closedRefreshCount)
    }


    @Test func panelSnapshotCanBeWrittenForAutomation() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.theme = .dark
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in
                completion([])
            }
        )
        defer { controller.stop() }
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-panel-snapshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        controller.start(showPanelOnLaunch: true)
        try controller.writePanelSnapshot(to: snapshotURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        #expect((attributes[.size] as? Int ?? 0) > 0)
    }

    @Test func settingsSnapshotCanBeWrittenForAutomation() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in
                completion([])
            }
        )
        defer { controller.stop() }
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-settings-snapshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        controller.start(showPanelOnLaunch: true)
        try controller.writeSettingsSnapshot(to: snapshotURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        #expect((attributes[.size] as? Int ?? 0) > 0)
    }

    @Test func iconButtonVisualStateResolvesHoverAndPressFeedback() {
        let idle = PTKIconButtonVisualState(isHovering: false, isPressed: false)
        let hovering = PTKIconButtonVisualState(isHovering: true, isPressed: false)
        let pressed = PTKIconButtonVisualState(isHovering: true, isPressed: true)

        #expect(idle.scale == 1)
        #expect(hovering.scale > idle.scale)
        #expect(hovering.backgroundOpacity > idle.backgroundOpacity)
        #expect(pressed.scale < idle.scale)
        #expect(pressed.backgroundOpacity > hovering.backgroundOpacity)
    }

    @Test func buttonInteractionSnapshotCanBeWrittenForAutomation() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        let controller = MenuBarController(
            settings: settings,
            serviceStatusLoader: { completion in
                completion([])
            }
        )
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-button-interaction-snapshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        try controller.writeButtonInteractionSnapshot(to: snapshotURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        #expect((attributes[.size] as? Int ?? 0) > 0)
    }
}

@MainActor
@Suite struct PortMonitorViewModelTests {
    @Test func contentViewUsesReadableUtilityPanelSize() {
        #expect(ContentView.panelSize.width == 392)
        #expect(ContentView.panelSize.height == 420)
    }

    @Test func openPortsFiltersAndSorts() {
        let viewModel = makeViewModel()
        viewModel.statuses = [
            PortStatus(port: 3000, isOpen: false),
            PortStatus(port: 3002, isOpen: true, pid: 1, processName: "node"),
            PortStatus(port: 3001, isOpen: true, pid: 2, processName: "vite")
        ]

        #expect(viewModel.openPorts.count == 2)
        #expect(viewModel.openPorts[0].port == 3001)
        #expect(viewModel.openPorts[1].port == 3002)
        #expect(viewModel.menuBarTitle == "PTK 2")
    }

    @Test func menuBarTitleShowsCount() {
        let viewModel = makeViewModel()
        viewModel.statuses = [
            PortStatus(port: 3000, isOpen: true),
            PortStatus(port: 3001, isOpen: false)
        ]

        #expect(viewModel.menuBarTitle == "PTK 1")
    }

    @Test func killFlowSetsAndClearsConfirmationTarget() {
        let viewModel = makeViewModel()
        let target = KillTarget(port: 3000, pid: 100, processName: "node")

        viewModel.requestKill(target)

        #expect(viewModel.killConfirmationTarget != nil)
        #expect(viewModel.killConfirmationTarget?.port == 3000)

        viewModel.cancelKill()

        #expect(viewModel.killConfirmationTarget == nil)
    }

    @Test func saveIntervalNotifiesSchedulerOwner() {
        var changedInterval: RefreshInterval?
        let viewModel = makeViewModel(onIntervalChange: { interval in
            changedInterval = interval
        })

        viewModel.saveInterval(.tenSeconds)

        #expect(viewModel.refreshInterval == .tenSeconds)
        #expect(changedInterval == .tenSeconds)
    }

    @Test func saveThemePersistsSelectionAndUpdatesViewModel() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        let viewModel = makeViewModel(settings: settings)

        viewModel.saveTheme(.light)

        let reloaded = AppSettings(store: store)
        #expect(viewModel.theme == .light)
        #expect(reloaded.theme == .light)
    }

    @Test func applyPresetPersistsExpressionAndRefreshes() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        var refreshCount = 0
        let viewModel = makeViewModel(
            settings: settings,
            onRefresh: {
                refreshCount += 1
            }
        )

        try viewModel.applyPreset(AppDefaults.portPresets[1])

        let reloaded = AppSettings(store: store)
        #expect(viewModel.portExpression == "3000-3009,5173-5182")
        #expect(reloaded.watchedPortsExpression == "3000-3009,5173-5182")
        #expect(refreshCount == 1)
    }

    @Test func customProfilesPersistApplyAndDelete() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        var refreshCount = 0
        let viewModel = makeViewModel(
            settings: settings,
            onRefresh: {
                refreshCount += 1
            }
        )

        try viewModel.saveCustomProfile(title: "Client A", expression: "3000,5173")
        #expect(viewModel.customPortProfiles.map(\.title) == ["Client A"])

        try viewModel.applyProfile(viewModel.customPortProfiles[0])
        #expect(viewModel.portExpression == "3000,5173")
        #expect(refreshCount == 1)

        viewModel.deleteCustomProfile(viewModel.customPortProfiles[0])
        #expect(viewModel.customPortProfiles.isEmpty)
        #expect(AppSettings(store: store).customPortProfiles.isEmpty)
    }

    @Test func profileOptionsExposePresetsAndCustomProfiles() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        var refreshCount = 0
        let viewModel = makeViewModel(
            settings: settings,
            onRefresh: { refreshCount += 1 }
        )

        try viewModel.saveCustomProfile(title: "Client A", expression: "3000,5173")

        #expect(viewModel.profileOptions.map(\.title).prefix(4) == ["Full Stack", "Frontend", "API", "Data"])
        #expect(viewModel.profileOptions.map(\.title).contains("Client A"))
        let option = try #require(viewModel.profileOptions.first { $0.title == "Client A" })
        try viewModel.applyProfileOption(option)

        #expect(viewModel.currentProfileTitle == "Client A")
        #expect(AppSettings(store: store).watchedPortsExpression == "3000,5173")
        #expect(refreshCount == 1)
    }


    @Test func customServicesPersistDeleteAndRefresh() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        var refreshCount = 0
        let viewModel = makeViewModel(
            settings: settings,
            onRefresh: {
                refreshCount += 1
            }
        )

        try viewModel.saveCustomServiceEndpoint(name: "RabbitMQ", portText: "5672")
        #expect(viewModel.customServiceEndpoints == [DatabaseEndpoint(name: "RabbitMQ", port: 5672)])
        #expect(refreshCount == 1)

        viewModel.deleteCustomServiceEndpoint(viewModel.customServiceEndpoints[0])
        #expect(viewModel.customServiceEndpoints.isEmpty)
        #expect(AppSettings(store: store).customServiceEndpoints.isEmpty)
        #expect(refreshCount == 2)
    }

    @Test func serviceStatusesGroupBuiltInAndCustomRows() {
        let viewModel = makeViewModel()
        viewModel.serviceStatuses = [
            ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
            ServiceStatus(name: "RabbitMQ", detail: "Port 5672", state: .stopped, group: .custom)
        ]

        #expect(viewModel.groupedServiceStatuses.map(\.title) == ["Built-in", "Custom"])
        #expect(viewModel.groupedServiceStatuses[0].statuses.map(\.name) == ["Docker"])
        #expect(viewModel.groupedServiceStatuses[1].statuses.map(\.name) == ["RabbitMQ"])
    }


    @Test func customServicesRejectNonNumericPortText() {
        let viewModel = makeViewModel()

        #expect(throws: AppSettingsError.invalidServicePort) {
            try viewModel.saveCustomServiceEndpoint(name: "Broken", portText: "nope")
        }
    }

    @Test func quickActionsForwardOpenAndCopyRequests() {
        var openedURL: URL?
        var copiedText: String?
        let viewModel = makeViewModel(
            onOpenLocalhost: { url in
                openedURL = url
            },
            onCopyText: { text in
                copiedText = text
            }
        )
        let status = PortStatus(port: 5173, isOpen: true, pid: 42, processName: "vite")
        viewModel.statuses = [status]

        viewModel.openLocalhost(for: status)
        #expect(openedURL?.absoluteString == "http://localhost:5173")

        viewModel.copyLocalhostURL(for: status)
        #expect(copiedText == "http://localhost:5173")

        viewModel.copyPortDetails(for: status)
        #expect(copiedText == """
        Port: 5173
        URL: http://localhost:5173
        PID: 42
        Process: vite
        """)

        viewModel.copyOpenPortsSummary()
        #expect(copiedText?.contains("5173") == true)
        #expect(copiedText?.contains("vite") == true)
    }

    @Test func copyPortDetailsIncludesKillUnavailableReasonWhenBlocked() {
        var copiedText: String?
        let viewModel = makeViewModel(
            onCopyText: { text in
                copiedText = text
            }
        )
        let status = PortStatus(
            port: 3000,
            isOpen: true,
            message: "ambiguous process lookup: port 3000 has PIDs 1, 2"
        )

        viewModel.copyPortDetails(for: status)

        #expect(copiedText?.contains("Port: 3000") == true)
        #expect(copiedText?.contains("Kill unavailable: 여러 listener") == true)
        #expect(copiedText?.contains("Detail: ambiguous process lookup") == true)
        #expect(copiedText?.contains("Hint:") == true)
    }
}

@MainActor private func makeViewModel(
    settings: AppSettings = AppSettings(store: InMemorySettingsStore()),
    onRefresh: @escaping () -> Void = {},
    onIntervalChange: @escaping (RefreshInterval) -> Void = { _ in },
    onOpenLocalhost: @escaping (URL) -> Void = { _ in },
    onCopyText: @escaping (String) -> Void = { _ in }
) -> PortMonitorViewModel {
    PortMonitorViewModel(
        settings: settings,
        killService: KillService(
            resolver: ProcessLookup(runner: FakeProcessRunner()),
            terminator: FakeProcessTerminator()
        ),
        parser: PortRangeParser(),
        onRefresh: onRefresh,
        onIntervalChange: onIntervalChange,
        onOpenLocalhost: onOpenLocalhost,
        onCopyText: onCopyText
    )
}

private final class FakeProcessRunner: ProcessRunning {
    func run(_ executable: String, arguments: [String]) throws -> ProcessRunResult {
        ProcessRunResult(exitCode: 0, stdout: "")
    }
}

private struct FakeSocketConnector: SocketConnecting {
    let openPorts: Set<UInt16>

    func isListening(host: String, port: UInt16, timeout: Double) -> Bool {
        openPorts.contains(port)
    }
}

private final class MutableFakeSocketConnector: SocketConnecting {
    var openPorts: Set<UInt16>

    init(openPorts: Set<UInt16>) {
        self.openPorts = openPorts
    }

    func isListening(host: String, port: UInt16, timeout: Double) -> Bool {
        openPorts.contains(port)
    }
}

private final class FakeProcessTerminator: ProcessTerminating {
    func terminate(pid: Int) -> String? { nil }
}
