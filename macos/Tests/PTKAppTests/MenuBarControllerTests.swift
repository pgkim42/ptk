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

    @Test func parserFailureSettlesOnlyPortBranchAndServiceStillPublishes() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "not-a-port"
        let serviceGate = BlockingGate()
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                Issue.record("Port worker must not run after parser failure")
                return []
            },
            serviceSnapshotWorker: { _ in
                serviceGate.wait()
                return ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Redis", detail: "Port 6379", state: .running)
                ])
            }
        )

        controller.performRefresh()

        #expect(controller.viewModel.isRefreshing)
        #expect(controller.viewModel.errorMessage?.hasPrefix("포트 설정 오류:") == true)
        #expect(await eventually { serviceGate.hasWaiter })
        serviceGate.open()
        #expect(await eventually {
            !controller.viewModel.isRefreshing
        })
        #expect(controller.viewModel.serviceStatuses.map(\.name) == ["Redis"])
        #expect(controller.viewModel.errorMessage?.hasPrefix("포트 설정 오류:") == true)
    }

    @Test func refreshSnapshotsSettingsAndCustomEndpointsBeforeWorkersRun() async throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        try settings.saveCustomServiceEndpoint(name: "RabbitMQ", port: 5672)
        let portGate = BlockingGate()
        let serviceGate = BlockingGate()
        let receivedPorts = LockedBox<[UInt16]>([])
        let receivedEndpoints = LockedBox<[DatabaseEndpoint]>([])
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { ports in
                portGate.wait()
                receivedPorts.set(ports)
                return []
            },
            serviceSnapshotWorker: { endpoints in
                serviceGate.wait()
                receivedEndpoints.set(endpoints)
                return ServiceSnapshot(statuses: [])
            }
        )

        controller.performRefresh()
        #expect(await eventually { portGate.hasWaiter && serviceGate.hasWaiter })

        settings.watchedPortsExpression = "4000"
        try settings.saveCustomServiceEndpoint(name: "NATS", port: 4222)
        portGate.open()
        serviceGate.open()

        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(receivedPorts.value == [3000])
        #expect(receivedEndpoints.value.map(\.name) == ["RabbitMQ"])
    }

    @Test func refreshKeepsProgressUntilBothBranchesSettle() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let portGate = BlockingGate()
        let serviceGate = BlockingGate()
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                portGate.wait()
                return [PortStatus(port: 3000, isOpen: true)]
            },
            serviceSnapshotWorker: { _ in
                serviceGate.wait()
                return ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Docker", detail: "Daemon", state: .running)
                ])
            }
        )

        controller.performRefresh()
        #expect(await eventually { portGate.hasWaiter && serviceGate.hasWaiter })
        #expect(controller.viewModel.isRefreshing)

        portGate.open()
        #expect(await eventually { controller.viewModel.statuses.count == 1 })
        #expect(controller.viewModel.isRefreshing)

        serviceGate.open()
        #expect(await eventually { !controller.viewModel.isRefreshing })
    }

    @Test func inFlightRefreshDoesNotStartDuplicateWorkersAndCompletionReopensScheduler() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let portGate = BlockingGate()
        let portCalls = LockedBox(0)
        let serviceCalls = LockedBox(0)
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                portCalls.withValue { $0 += 1 }
                portGate.wait()
                return []
            },
            serviceSnapshotWorker: { _ in
                serviceCalls.withValue { $0 += 1 }
                return ServiceSnapshot(statuses: [])
            }
        )

        controller.performRefresh()
        #expect(await eventually { portGate.hasWaiter })
        controller.performRefresh()
        controller.performRefresh()
        #expect(portCalls.value == 1)
        #expect(serviceCalls.value == 1)

        portGate.open()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        controller.performRefresh()
        #expect(await eventually { portCalls.value == 2 })
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(serviceCalls.value == 2)
    }

    @Test func portAndServiceFailuresRetainPriorBranchDataAndExposeBothErrors() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let shouldFail = LockedBox(false)
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                if shouldFail.value {
                    throw TestFailure("port failed")
                }
                return [PortStatus(port: 3000, isOpen: true)]
            },
            serviceSnapshotWorker: { _ in
                if shouldFail.value {
                    throw TestFailure("service failed")
                }
                return ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Docker", detail: "Daemon", state: .running)
                ])
            }
        )

        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        shouldFail.set(true)
        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })

        #expect(controller.viewModel.statuses.map(\.port) == [3000])
        #expect(controller.viewModel.serviceStatuses.map(\.name) == ["Docker"])
        #expect(controller.viewModel.errorMessage?.contains("port failed") == true)
        #expect(controller.viewModel.errorMessage?.contains("service failed") == true)
    }

    @Test func blockedScanWorkerDoesNotBlockMainActorHeartbeat() async {
        let gate = BlockingGate()
        let heartbeat = LockedBox(false)
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in
                gate.wait()
                return []
            },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )

        controller.performRefresh()
        #expect(await eventually { gate.hasWaiter })
        Task { @MainActor in
            heartbeat.set(true)
        }
        #expect(await eventually { heartbeat.value })

        gate.open()
        #expect(await eventually { !controller.viewModel.isRefreshing })
    }

    @Test func stopCancelsOwnedWorkAndPreventsLatePublication() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let portGate = BlockingGate()
        let serviceGate = BlockingGate()
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in
                portGate.wait()
                return [PortStatus(port: 3000, isOpen: true)]
            },
            serviceSnapshotWorker: { _ in
                serviceGate.wait()
                return ServiceSnapshot(statuses: [
                    ServiceStatus(name: "Late", detail: "Late", state: .running)
                ])
            }
        )

        controller.performRefresh()
        #expect(await eventually { portGate.hasWaiter && serviceGate.hasWaiter })
        controller.stop()
        #expect(!controller.viewModel.isRefreshing)

        portGate.open()
        serviceGate.open()
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(controller.viewModel.statuses.isEmpty)
        #expect(controller.viewModel.serviceStatuses.isEmpty)
        controller.performRefresh()
        #expect(controller.viewModel.statuses.isEmpty)
    }

    @Test func killWorkerRunsOffMainActorAndDuplicateConfirmationUsesOneToken() async {
        let gate = BlockingGate()
        let killCalls = LockedBox(0)
        let heartbeat = LockedBox(false)
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
            killWorker: { _ in
                killCalls.withValue { $0 += 1 }
                gate.wait()
            }
        )
        let target = KillTarget(port: 3000, pid: 100, processName: "node")

        controller.viewModel.requestKill(target)
        controller.viewModel.confirmKill()
        controller.viewModel.confirmKill()
        #expect(await eventually { gate.hasWaiter })
        #expect(controller.viewModel.isTerminatingProcess)
        Task { @MainActor in
            heartbeat.set(true)
        }
        #expect(await eventually { heartbeat.value })
        #expect(killCalls.value == 1)

        gate.open()
        #expect(await eventually { !controller.viewModel.isTerminatingProcess })
        #expect(killCalls.value == 1)
        #expect(await eventually { controller.lastRefreshTriggerForTesting == .kill })
        #expect(await eventually { !controller.viewModel.isRefreshing })
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
            #expect(await eventually { !controller.viewModel.isRefreshing })
            #expect(refreshCalls.value == 1)
            #expect(controller.lastRefreshTriggerForTesting == .kill)
            #expect(controller.viewModel.killErrorMessage == failureMessage)
        }
    }

    @Test func stopInvalidatesBlockedKillAndSuppressesLateRefresh() async {
        let gate = BlockingGate()
        let refreshCalls = LockedBox(0)
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in
                refreshCalls.withValue { $0 += 1 }
                return []
            },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
            killWorker: { _ in gate.wait() }
        )

        controller.viewModel.requestKill(KillTarget(port: 3000, pid: 100, processName: "node"))
        controller.viewModel.confirmKill()
        #expect(await eventually { gate.hasWaiter })
        controller.stop()
        gate.open()
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(!controller.viewModel.isTerminatingProcess)
        #expect(refreshCalls.value == 0)
        #expect(controller.lastRefreshTriggerForTesting == nil)
    }

    @Test func triggerClassesAreWiredDistinctly() async throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) },
            killWorker: { _ in }
        )
        defer { controller.stop() }

        controller.start()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.lastRefreshTriggerForTesting == .startup)

        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.lastRefreshTriggerForTesting == .manual)

        controller.fireTimerForTesting()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.lastRefreshTriggerForTesting == .timer)

        try controller.viewModel.saveExpression("3000")
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.lastRefreshTriggerForTesting == .settings)

        controller.viewModel.requestKill(KillTarget(port: 3000, pid: 1, processName: "node"))
        controller.viewModel.confirmKill()
        #expect(await eventually { !controller.viewModel.isTerminatingProcess })
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.lastRefreshTriggerForTesting == .kill)
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

    @Test func refreshRecordsRecentPortChangesAfterInitialBaseline() async {
        let openPorts = LockedBox<Set<UInt16>>([])
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000"
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { ports in
                ports.map { PortStatus(port: $0, isOpen: openPorts.value.contains($0)) }
            },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )

        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        openPorts.set([3000])
        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })

        #expect(controller.viewModel.recentPortChanges.map(\.kind) == [.opened])
        #expect(controller.viewModel.recentPortChanges.map(\.port) == [3000])
    }

    @Test func refreshStoresDockerContainerRowsFromServiceSnapshot() async {
        let dockerRows = [
            DockerContainerPortRow(id: "container-api", name: "api", detail: "4000 -> 4000")
        ]
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in
                ServiceSnapshot(
                    statuses: [ServiceStatus(name: "Docker", detail: "Daemon", state: .running)],
                    dockerContainerRows: dockerRows
                )
            }
        )

        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.viewModel.serviceStatuses.map(\.name) == ["Docker"])
        #expect(controller.viewModel.dockerContainerRows == dockerRows)
    }

    @Test func panelCadenceSwitchesBetweenQuietAndConfiguredIntervals() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.refreshInterval = .tenSeconds
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        defer { controller.stop() }

        controller.start(showPanelOnLaunch: true)
        #expect(await eventually { !controller.viewModel.isRefreshing })
        controller.applyPanelClosedForTesting()
        #expect(controller.activeRefreshCadenceSeconds == MenuBarController.quietRefreshCadence)

        controller.applyPanelOpenedForTesting()
        #expect(await eventually { !controller.viewModel.isRefreshing })
        #expect(controller.activeRefreshCadenceSeconds == RefreshInterval.tenSeconds.rawValue)
        #expect(controller.currentRefreshTimerInterval == RefreshInterval.tenSeconds.rawValue)
        #expect(controller.lastRefreshTriggerForTesting == .manual)
    }

    @Test func panelAndSettingsSnapshotsCanBeWrittenForAutomation() async throws {
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        defer { controller.stop() }
        let panelURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-panel-\(UUID().uuidString).png")
        let settingsURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-settings-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: panelURL)
            try? FileManager.default.removeItem(at: settingsURL)
        }

        controller.start(showPanelOnLaunch: true)
        #expect(await eventually { !controller.viewModel.isRefreshing })
        try controller.writePanelSnapshot(to: panelURL)
        try controller.writeSettingsSnapshot(to: settingsURL)

        let panelAttributes = try FileManager.default.attributesOfItem(atPath: panelURL.path)
        let settingsAttributes = try FileManager.default.attributesOfItem(atPath: settingsURL.path)
        #expect((panelAttributes[.size] as? Int ?? 0) > 0)
        #expect((settingsAttributes[.size] as? Int ?? 0) > 0)
    }
    @Test func refreshAppliesSymbolMenuBarButtonState() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000,3001"
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { ports in
                ports.map { PortStatus(port: $0, isOpen: true) }
            },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        defer { controller.stop() }

        controller.start()
        #expect(await eventually { !controller.viewModel.isRefreshing })

        #expect(controller.menuBarButtonStateForTesting == MenuBarButtonState(
            title: "2",
            hasImage: true,
            toolTip: "PTK · 2 open ports",
            accessibilityLabel: "PTK, 2 open ports"
        ))
    }

    @Test func recentPortChangesRemainCappedAndTrackIdentityChanges() async {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.watchedPortsExpression = "3000-3004"
        let scannedStatuses = LockedBox(
            (UInt16(3000)...UInt16(3004)).map { PortStatus(port: $0, isOpen: false) }
        )
        let controller = MenuBarController(
            settings: settings,
            portScanWorker: { _ in scannedStatuses.value },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )

        controller.performRefresh()
        #expect(await eventually { !controller.viewModel.isRefreshing })

        for port in UInt16(3000)...UInt16(3004) {
            scannedStatuses.withValue { statuses in
                let index = Int(port - 3000)
                statuses[index] = PortStatus(
                    port: port,
                    isOpen: true,
                    pid: Int(port),
                    processName: port == 3004 ? "vite" : "node"
                )
            }
            controller.performRefresh()
            #expect(await eventually { !controller.viewModel.isRefreshing })
        }

        #expect(controller.viewModel.recentPortChanges.count == 4)
        #expect(controller.viewModel.recentPortChanges.map(\.port) == [3004, 3003, 3002, 3001])
        #expect(controller.viewModel.recentPortChanges.first?.processName == "vite")
        #expect(controller.viewModel.menuBarStatusContent.countText == "5")
    }

    @Test func startShowsPanelImmediatelyForAutomation() async {
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        defer { controller.stop() }

        controller.start(showPanelOnLaunch: true)
        #expect(await eventually { !controller.viewModel.isRefreshing })

        #expect(controller.isPanelVisible)
        #expect(MenuBarController.quietRefreshCadence > RefreshInterval.allCases.map(\.rawValue).max()!)
    }

    @Test func dockerRowsCanBeRenderedInPanelSnapshot() async throws {
        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in
                ServiceSnapshot(
                    statuses: [ServiceStatus(name: "Docker", detail: "Daemon", state: .running)],
                    dockerContainerRows: [
                        DockerContainerPortRow(
                            id: "container-api",
                            name: "very-long-api-container-name",
                            detail: "4000 -> 4000, 9229 -> 9229, +1"
                        )
                    ]
                )
            }
        )
        defer { controller.stop() }
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-docker-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        controller.start(showPanelOnLaunch: true)
        #expect(await eventually { !controller.viewModel.isRefreshing })
        try controller.writePanelSnapshot(to: snapshotURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        #expect(controller.viewModel.dockerContainerRows.count == 1)
        #expect((attributes[.size] as? Int ?? 0) > 0)
    }

    @Test func iconButtonVisualStateAndInteractionSnapshotRemainAvailable() throws {
        let idle = PTKIconButtonVisualState(isHovering: false, isPressed: false)
        let hovering = PTKIconButtonVisualState(isHovering: true, isPressed: false)
        let pressed = PTKIconButtonVisualState(isHovering: true, isPressed: true)
        #expect(hovering.scale > idle.scale)
        #expect(pressed.scale < idle.scale)
        #expect(pressed.backgroundOpacity > hovering.backgroundOpacity)

        let controller = MenuBarController(
            settings: AppSettings(store: InMemorySettingsStore()),
            portScanWorker: { _ in [] },
            serviceSnapshotWorker: { _ in ServiceSnapshot(statuses: []) }
        )
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "ptk-button-\(UUID().uuidString).png")
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

    @Test func confirmKillGuardsDuplicatesAndClearsProgressOnSuccess() async {
        var killCalls = 0
        let viewModel = makeViewModel(onKill: { _ in
            killCalls += 1
            await Task.yield()
            return .settled(errorMessage: nil)
        })
        let target = KillTarget(port: 3000, pid: 100, processName: "node")

        viewModel.requestKill(target)
        viewModel.confirmKill()
        viewModel.confirmKill()

        #expect(viewModel.killConfirmationTarget == nil)
        #expect(viewModel.isTerminatingProcess)
        #expect(await eventually { !viewModel.isTerminatingProcess })
        #expect(killCalls == 1)
        #expect(viewModel.killErrorMessage == nil)
    }

    @Test func confirmKillPublishesExactAsyncErrorAndClearsProgress() async {
        let expectedError = "PID changed from 100 to 101; refresh and try again"
        let viewModel = makeViewModel(onKill: { _ in
            .settled(errorMessage: expectedError)
        })

        viewModel.requestKill(KillTarget(port: 3000, pid: 100, processName: "node"))
        viewModel.confirmKill()

        #expect(await eventually { !viewModel.isTerminatingProcess })
        #expect(viewModel.killErrorMessage == expectedError)
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
    onSettingsRefresh: (() -> Void)? = nil,
    onKill: @escaping @MainActor (KillTarget) async -> KillRequestResult = { _ in .invalidated },
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

    func wait() {
        condition.lock()
        waiterPresent = true
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

private final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let storage = LockedBox<[String: ProcessRunResult]>([:])

    var results: [String: ProcessRunResult] {
        get { storage.value }
        set { storage.set(newValue) }
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return storage.value[key] ?? ProcessRunResult(exitCode: 0, stdout: "")
    }
}

private struct FakeSocketConnector: SocketConnecting {
    let openPorts: Set<UInt16>

    func isListening(host: String, port: UInt16, timeout: Double) -> Bool {
        openPorts.contains(port)
    }
}

private final class MutableFakeSocketConnector: SocketConnecting, @unchecked Sendable {
    private let storage: LockedBox<Set<UInt16>>

    init(openPorts: Set<UInt16>) {
        storage = LockedBox(openPorts)
    }

    var openPorts: Set<UInt16> {
        get { storage.value }
        set { storage.set(newValue) }
    }

    func isListening(host: String, port: UInt16, timeout: Double) -> Bool {
        storage.value.contains(port)
    }
}

private final class FakeProcessTerminator: ProcessTerminating, @unchecked Sendable {
    func terminate(pid: Int) -> String? { nil }
}
