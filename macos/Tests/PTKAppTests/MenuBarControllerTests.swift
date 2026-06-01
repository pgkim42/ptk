import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
@Suite struct MenuBarControllerTests {
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
}

@MainActor
@Suite struct PortMonitorViewModelTests {
    @Test func contentViewUsesCompactUtilityPanelSize() {
        #expect(ContentView.panelSize.width == 352)
        #expect(ContentView.panelSize.height == 352)
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
}

@MainActor private func makeViewModel(
    onIntervalChange: @escaping (RefreshInterval) -> Void = { _ in }
) -> PortMonitorViewModel {
    PortMonitorViewModel(
        settings: AppSettings(store: InMemorySettingsStore()),
        killService: KillService(
            resolver: ProcessLookup(runner: FakeProcessRunner()),
            terminator: FakeProcessTerminator()
        ),
        parser: PortRangeParser(),
        onRefresh: {},
        onIntervalChange: onIntervalChange
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

private final class FakeProcessTerminator: ProcessTerminating {
    func terminate(pid: Int) -> String? { nil }
}
