import Foundation
import AppKit
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

    @Test func serviceCompositionPolicyFiltersDefaultPortsAndPreservesOrder() {
        let policy = ServiceStatusCompositionPolicy(defaultDatabaseEndpoints: [
            DatabaseEndpoint(name: "PostgreSQL", port: 5432),
            DatabaseEndpoint(name: "Redis", port: 6379)
        ])
        let customEndpoints = [
            DatabaseEndpoint(name: "Custom Postgres", port: 5432),
            DatabaseEndpoint(name: "RabbitMQ", port: 5672)
        ]

        let filteredEndpoints = policy.customEndpointsExcludingBuiltInPorts(customEndpoints)
        let composedStatuses = policy.compose(
            defaultStatuses: [
                ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
                ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .stopped)
            ],
            customStatuses: [
                ServiceStatus(name: "RabbitMQ", detail: "Port 5672", state: .running, group: .custom)
            ]
        )

        #expect(filteredEndpoints == [DatabaseEndpoint(name: "RabbitMQ", port: 5672)])
        #expect(composedStatuses.map(\.name) == ["Docker", "PostgreSQL", "RabbitMQ"])
        #expect(composedStatuses.map(\.group) == [.builtIn, .builtIn, .custom])
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
        #expect(controller.viewModel.menuBarStatusContent.countText == "2")
    }

    @Test func refreshStoresDockerContainerRowsFromServiceSnapshot() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let dockerRows = [
            DockerContainerPortRow(
                id: "container-api",
                name: "api",
                detail: "4000 -> 4000"
            )
        ]
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: FakeSocketConnector(openPorts: []),
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceSnapshotLoader: { completion in
                completion(ServiceSnapshot(
                    statuses: [ServiceStatus(name: "Docker", detail: "Daemon", state: .running)],
                    dockerContainerRows: dockerRows
                ))
            }
        )

        controller.performRefresh()

        #expect(controller.viewModel.serviceStatuses.map(\.name) == ["Docker"])
        #expect(controller.viewModel.dockerContainerRows == dockerRows)
    }

    @Test func refreshAppliesSymbolMenuBarButtonState() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000,3001"
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: FakeSocketConnector(openPorts: [3000, 3001]),
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceStatusLoader: { completion in
                completion([])
            }
        )
        defer { controller.stop() }

        controller.start()
        controller.performRefresh()

        #expect(controller.menuBarButtonStateForTesting == MenuBarButtonState(
            title: "2",
            hasImage: true,
            toolTip: "PTK · 2 open ports",
            accessibilityLabel: "PTK, 2 open ports"
        ))
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

    @Test func recentPortChangesAreCappedAtFourNewestFirst() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000-3004"
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
        for port in UInt16(3000)...UInt16(3004) {
            connector.openPorts.insert(port)
            controller.performRefresh()
        }

        #expect(controller.viewModel.recentPortChanges.count == 4)
        #expect(controller.viewModel.recentPortChanges.map(\.kind) == [.opened, .opened, .opened, .opened])
        #expect(controller.viewModel.recentPortChanges.map(\.port) == [3004, 3003, 3002, 3001])
    }

    @Test func recentPortChangesRecordProcessIdentityChangesNewestFirst() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let connector = MutableFakeSocketConnector(openPorts: [3000])
        let runner = FakeProcessRunner()
        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            node    111 me   1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
            """
        )
        runner.results["ps -p 111 -o comm="] = ProcessRunResult(exitCode: 0, stdout: "/usr/local/bin/node\n")
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: connector,
                lookup: ProcessLookup(runner: runner)
            ),
            serviceStatusLoader: { _ in }
        )

        controller.performRefresh()
        #expect(controller.viewModel.recentPortChanges.isEmpty)

        runner.results["lsof -nP -iTCP -sTCP:LISTEN"] = ProcessRunResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            vite    222 me   1u IPv4 0x2    0t0      TCP *:3000 (LISTEN)
            """
        )
        runner.results["ps -p 222 -o comm="] = ProcessRunResult(exitCode: 0, stdout: "vite\n")
        controller.performRefresh()

        let change = controller.viewModel.recentPortChanges.first
        #expect(change?.kind == .changed)
        #expect(change?.port == 3000)
        #expect(change?.pid == 222)
        #expect(change?.processName == "vite")
        #expect(controller.viewModel.recentPortChanges.count == 1)
    }

    @Test func recentChangesDoNotAlterMenuBarStatusContent() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
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
        let baselineContent = controller.viewModel.menuBarStatusContent

        connector.openPorts = [3000]
        controller.performRefresh()

        #expect(controller.viewModel.recentPortChanges.map(\.kind) == [.opened])
        #expect(controller.viewModel.menuBarStatusContent == MenuBarStatusContent(
            symbolName: "network",
            countText: "1",
            toolTip: "PTK · 1 open port",
            accessibilityLabel: "PTK, 1 open port"
        ))
        #expect(baselineContent == MenuBarStatusContent(
            symbolName: "network",
            countText: "0",
            toolTip: "PTK · 0 open ports",
            accessibilityLabel: "PTK, 0 open ports"
        ))
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

    @Test func panelSnapshotRendersRecentPortChangesForAutomation() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.theme = .dark
        settings.watchedPortsExpression = "3000"
        let connector = MutableFakeSocketConnector(openPorts: [])
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: connector,
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceStatusLoader: { completion in completion([]) }
        )
        defer { controller.stop() }
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-recent-changes-panel-snapshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        controller.start(showPanelOnLaunch: true)
        controller.performRefresh()
        connector.openPorts = [3000]
        controller.performRefresh()
        try controller.writePanelSnapshot(to: snapshotURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        #expect((attributes[.size] as? Int ?? 0) > 0)
        #expect(controller.viewModel.recentPortChanges.map(\.kind) == [.opened])
    }

    @Test func panelSnapshotCanRenderDockerContainerRowsForAutomation() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.theme = .dark
        settings.watchedPortsExpression = "3000"
        let controller = MenuBarController(
            settings: settings,
            scanner: PortScanner(
                connector: FakeSocketConnector(openPorts: []),
                lookup: ProcessLookup(runner: FakeProcessRunner())
            ),
            serviceSnapshotLoader: { completion in
                completion(ServiceSnapshot(
                    statuses: [
                        ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
                        ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .stopped)
                    ],
                    dockerContainerRows: [
                        DockerContainerPortRow(
                            id: "container-very-long-api-name",
                            name: "very-long-api-container-name",
                            detail: "4000 -> 4000, 9229 -> 9229, 9230 -> 9230, +1"
                        ),
                        DockerContainerPortRow(
                            id: "container-web",
                            name: "web",
                            detail: "3000 -> 80"
                        )
                    ]
                ))
            }
        )
        defer { controller.stop() }
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-docker-container-rows-snapshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        controller.start(showPanelOnLaunch: true)
        try controller.writePanelSnapshot(to: snapshotURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        #expect(controller.viewModel.dockerContainerRows.count == 2)
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

    @Test func menuBarStatusCountsOpenPorts() {
        let viewModel = makeViewModel()
        viewModel.statuses = [
            PortStatus(port: 3000, isOpen: false),
            PortStatus(port: 3002, isOpen: true, pid: 1, processName: "node"),
            PortStatus(port: 3001, isOpen: true, pid: 2, processName: "vite")
        ]

        #expect(viewModel.openPorts.count == 2)
        #expect(viewModel.openPorts[0].port == 3001)
        #expect(viewModel.openPorts[1].port == 3002)
        #expect(viewModel.menuBarStatusContent == MenuBarStatusContent(
            symbolName: "network",
            countText: "2",
            toolTip: "PTK · 2 open ports",
            accessibilityLabel: "PTK, 2 open ports"
        ))
    }

    @Test func menuBarStatusUsesSingularCopyForOneOpenPort() {
        let viewModel = makeViewModel()
        viewModel.statuses = [
            PortStatus(port: 3000, isOpen: true),
            PortStatus(port: 3001, isOpen: false)
        ]

        #expect(viewModel.menuBarStatusContent.countText == "1")
        #expect(viewModel.menuBarStatusContent.toolTip == "PTK · 1 open port")
        #expect(viewModel.menuBarStatusContent.accessibilityLabel == "PTK, 1 open port")
    }

    @Test func recentPortChangePresenterRendersKindIconAndTimeContext() {
        let presenter = PortChangePresenter()
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_700_000_125)

        let opened = presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, pid: 11, processName: "/usr/local/bin/node", occurredAt: occurredAt),
            relativeTo: now
        )
        let closed = presenter.displayData(
            for: PortChange(port: 3001, kind: .closed, occurredAt: occurredAt),
            relativeTo: now
        )
        let changed = presenter.displayData(
            for: PortChange(port: 3002, kind: .changed, pid: 21, processName: "vite", occurredAt: occurredAt),
            relativeTo: now
        )

        #expect(opened.systemImageName != closed.systemImageName)
        #expect(closed.systemImageName != changed.systemImageName)
        #expect(opened.primaryText == "Port 3000 열림")
        #expect(closed.primaryText == "Port 3001 닫힘")
        #expect(changed.primaryText == "Port 3002 변경")
        #expect(opened.detailText == "node · PID 11")
        #expect(changed.detailText == "vite · PID 21")
        #expect(opened.timeText == "2분 전")
        #expect(opened.accessibilityText.contains("Port 3000 열림"))
        #expect(opened.accessibilityText.contains("2분 전"))
    }

    @Test func recentPortChangePresenterHelpAndAccessibilityMirrorRowInformation() {
        let presenter = PortChangePresenter()
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_700_003_700)

        let withProcess = presenter.displayData(
            for: PortChange(port: 5173, kind: .changed, pid: 42, processName: "/opt/homebrew/bin/vite", occurredAt: occurredAt),
            relativeTo: now
        )
        let withoutProcess = presenter.displayData(
            for: PortChange(port: 3000, kind: .closed, occurredAt: occurredAt),
            relativeTo: now
        )

        #expect(withProcess.primaryText == "Port 5173 변경")
        #expect(withProcess.detailText == "vite · PID 42")
        #expect(withProcess.timeText == "1시간 전")
        #expect(withProcess.helpText == "Port 5173 변경 · vite · PID 42 · 1시간 전")
        #expect(withProcess.accessibilityText == withProcess.helpText)

        #expect(withoutProcess.detailText == nil)
        #expect(withoutProcess.helpText == "Port 3000 닫힘 · 1시간 전")
        #expect(withoutProcess.accessibilityText == withoutProcess.helpText)
    }

    @Test func recentPortChangePresenterCoversRelativeTimeBoundaries() {
        let presenter = PortChangePresenter()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_700_000_030)),
            relativeTo: now
        ).timeText == "방금")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_999_941)),
            relativeTo: now
        ).timeText == "방금")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_999_940)),
            relativeTo: now
        ).timeText == "1분 전")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_996_401)),
            relativeTo: now
        ).timeText == "59분 전")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_996_400)),
            relativeTo: now
        ).timeText == "1시간 전")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_913_601)),
            relativeTo: now
        ).timeText == "23시간 전")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_913_600)),
            relativeTo: now
        ).timeText == "1일 전")
        #expect(presenter.displayData(
            for: PortChange(port: 3000, kind: .opened, occurredAt: Date(timeIntervalSince1970: 1_699_740_800)),
            relativeTo: now
        ).timeText == "3일 전")
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

    @Test func customServiceEmptyMessageAppearsOnlyBeforeCustomEndpointsExist() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        let viewModel = makeViewModel(settings: settings)

        #expect(viewModel.customServiceEmptyMessage == "No custom services yet. Add read-only port checks in Settings.")

        try viewModel.saveCustomServiceEndpoint(name: "RabbitMQ", portText: "5672")

        #expect(viewModel.customServiceEmptyMessage == nil)
        #expect(viewModel.showsServiceGroupHeaders == false)
    }

    @Test func customEmptyStateKeepsBuiltInGroupHeaderVisible() {
        let viewModel = makeViewModel()
        viewModel.serviceStatuses = [
            ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
            ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .stopped)
        ]

        #expect(viewModel.groupedServiceStatuses.map(\.title) == ["Built-in"])
        #expect(viewModel.customServiceEmptyMessage != nil)
        #expect(viewModel.showsServiceGroupHeaders)
    }

    @Test func serviceSummaryExcludesDockerContainerRows() {
        let viewModel = makeViewModel()
        viewModel.serviceStatuses = [
            ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
            ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .stopped)
        ]
        viewModel.dockerContainerRows = [
            DockerContainerPortRow(id: "container-api", name: "api", detail: "4000 -> 4000"),
            DockerContainerPortRow(id: "container-web", name: "web", detail: "3000 -> 80")
        ]

        #expect(viewModel.serviceStatusSummary == "1/2")
        #expect(viewModel.groupedServiceStatuses[0].statuses.count == 2)
        #expect(viewModel.groupedServiceStatuses[0].statuses[0].kind == .dockerDaemon)
    }

    @Test func dockerContainerURLCopyUsesStructuredCandidateOnly() {
        var copiedText: String?
        let viewModel = makeViewModel(onCopyText: { copiedText = $0 })
        let copyable = DockerContainerPortRow(
            id: "container-web",
            name: "web",
            detail: "3000 -> 80",
            copyCandidates: [
                DockerPortCopyCandidate(label: "3000", urlString: "http://localhost:3000")
            ]
        )
        let ambiguous = DockerContainerPortRow(
            id: "container-api",
            name: "api",
            detail: "4000 -> 4000, 9229 -> 9229"
        )
        let malformedSummary = DockerContainerPortRow(
            id: "container-more-1",
            name: "+1 more",
            detail: "1 hidden container",
            isSummary: true,
            copyCandidates: [
                DockerPortCopyCandidate(label: "3000", urlString: "http://localhost:3000")
            ]
        )

        viewModel.copyDockerContainerURL(for: copyable)
        #expect(copiedText == "http://localhost:3000")

        copiedText = nil
        viewModel.copyDockerContainerURL(for: ambiguous)
        #expect(copiedText == nil)

        copiedText = nil
        viewModel.copyDockerContainerURL(for: malformedSummary)
        #expect(copiedText == nil)
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

    @Test func diagnosticPresenterPreservesExactOutputForBlockedStates() throws {
        let presenter = KillUnavailableDiagnosticPresenter()
        let ambiguous = try #require(presenter.diagnostic(for: PortStatus(
            port: 3000,
            isOpen: true,
            message: "ambiguous process lookup: port 3000 has PIDs 1, 2"
        )))
        let lookupFailure = try #require(presenter.diagnostic(for: PortStatus(
            port: 3001,
            isOpen: true,
            message: "lsof failed"
        )))
        let missingPID = try #require(presenter.diagnostic(for: PortStatus(port: 3002, isOpen: true)))
        let missingProcessName = try #require(presenter.diagnostic(for: PortStatus(port: 3003, isOpen: true, pid: 333)))

        #expect(ambiguous.title == "여러 listener가 있어 안전하게 종료할 수 없음")
        #expect(ambiguous.detail == "ambiguous process lookup: port 3000 has PIDs 1, 2")
        #expect(ambiguous.hint == "포트 3000를 점유한 프로세스를 터미널에서 직접 확인한 뒤 정리하세요.")
        #expect(lookupFailure.title == "프로세스 조회 실패로 안전하게 종료할 수 없음")
        #expect(lookupFailure.detail == "lsof failed")
        #expect(lookupFailure.hint == "새로고침 후에도 반복되면 lsof/ps 결과를 확인하세요.")
        #expect(missingPID.title == "PID를 찾을 수 없어 안전하게 종료할 수 없음")
        #expect(missingPID.detail == nil)
        #expect(missingPID.hint == "프로세스 조회 권한 또는 포트 상태를 확인한 뒤 다시 새로고침하세요.")
        #expect(missingProcessName.title == "프로세스 이름을 확인할 수 없어 안전하게 종료할 수 없음")
        #expect(missingProcessName.detail == nil)
        #expect(missingProcessName.hint == "PID 333의 프로세스가 바뀌었을 수 있으니 다시 새로고침하세요.")
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
    var results: [String: ProcessRunResult] = [:]

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return results[key] ?? ProcessRunResult(exitCode: 0, stdout: "")
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
