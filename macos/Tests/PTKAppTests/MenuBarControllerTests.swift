import AppKit
import Testing
@testable import PTKApp
@testable import PTKCore

@MainActor
@Suite struct MenuBarControllerTests {
    @Test func controlMenuIncludesWatchedPortSettingsAction() {
        let controller = MenuBarController(settings: AppSettings(store: InMemorySettingsStore()))
        let items = MenuBarMenuBuilder(target: controller).controlMenuItems(model: MenuModel(statuses: []))

        #expect(items.map(\.title) == ["새로고침", "감시 포트 설정...", "새로고침 주기"])
        #expect(items[1].action == #selector(MenuBarController.editWatchedPorts(_:)))
        #expect(items[1].target === controller)
    }

    @Test func serviceMenuItemsRenderReadOnlyStatuses() {
        let controller = MenuBarController(settings: AppSettings(store: InMemorySettingsStore()))
        let items = MenuBarMenuBuilder(target: controller).serviceMenuItems(statuses: [
            ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
            ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .stopped)
        ])

        #expect(items.map(\.title) == [
            "서비스 상태",
            "Docker · Daemon · Running",
            "PostgreSQL · Port 5432 · Stopped"
        ])
        #expect(items.allSatisfy { !$0.isEnabled })
        #expect(items.allSatisfy { $0.action == nil })
    }

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
