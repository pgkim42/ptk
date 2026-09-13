import AppKit
import PTKCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController: MenuBarController
    private let showPanelOnLaunch: Bool
    private let snapshotURL: URL?
    private let snapshotKind: String
    private let notificationClient: UserNotificationClient?

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let snapshotURL = environment["PTK_QA_SNAPSHOT_PATH"].map(URL.init(fileURLWithPath:))
        let snapshotKind = Self.effectiveSnapshotKind(
            requestedKind: environment["PTK_QA_SNAPSHOT_KIND"] ?? "panel",
            snapshotURL: snapshotURL
        )
        let settings = snapshotURL == nil
            ? AppSettings()
            : AppSettings(store: InMemorySettingsStore())
        if snapshotURL != nil,
           let rawTheme = environment["PTK_QA_THEME"],
           let theme = AppTheme(rawValue: rawTheme) {
            settings.theme = theme
        }
        if snapshotKind == "panel-docker" {
            settings.watchedPortsExpression = "3000-3009,5173-5182,4200-4209,8080-8089"
        } else if snapshotKind == "panel-dense" {
            settings.watchedPortsExpression = "3000-3003"
        }
        self.snapshotURL = snapshotURL
        self.snapshotKind = snapshotKind
        showPanelOnLaunch = environment["PTK_QA_SHOW_PANEL"] == "1" || snapshotURL != nil
        let notificationClient: UserNotificationClient?
        if snapshotURL == nil, Self.canUseUserNotifications(bundleIdentifier: Bundle.main.bundleIdentifier) {
            notificationClient = UserNotificationClient()
        } else {
            notificationClient = nil
        }
        self.notificationClient = notificationClient
        let scanner: PortScanner
        let serviceSnapshotWorker: ServiceSnapshotWorker?
        if snapshotKind == "panel-docker" {
            scanner = Self.dockerPanelSnapshotScanner
            serviceSnapshotWorker = { _ in Self.dockerPanelSnapshot() }
        } else if snapshotKind == "panel-dense" {
            scanner = Self.densePanelSnapshotScanner
            serviceSnapshotWorker = { _ in Self.densePanelSnapshot() }
        } else {
            scanner = PortScanner()
            serviceSnapshotWorker = nil
        }
        if let notificationClient {
            menuBarController = MenuBarController(
                settings: settings,
                scanner: scanner,
                serviceSnapshotWorker: serviceSnapshotWorker,
                notificationPermission: notificationClient,
                notificationDelivery: notificationClient,
                notificationResponseHandler: notificationClient
            )
        } else {
            let snapshotClient = SnapshotNotificationClient()
            menuBarController = MenuBarController(
                settings: settings,
                scanner: scanner,
                serviceSnapshotWorker: serviceSnapshotWorker,
                notificationPermission: snapshotClient,
                notificationDelivery: snapshotClient
            )
        }
        super.init()
    }

    static func canUseUserNotifications(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return !bundleIdentifier.isEmpty
    }

    static func effectiveSnapshotKind(requestedKind: String, snapshotURL: URL?) -> String {
        snapshotURL == nil ? "panel" : requestedKind
    }
    private static var dockerPanelSnapshotScanner: PortScanner {
        PortScanner(
            connector: SnapshotSocketConnector(openPorts: [3000, 5173]),
            lookup: ProcessLookup(
                runner: SnapshotProcessRunner(),
                startTime: { _ in ProcessStartTime(seconds: 1, microseconds: 0) }
            )
        )
    }

    private static var densePanelSnapshotScanner: PortScanner {
        PortScanner(
            connector: SnapshotSocketConnector(openPorts: [3000, 3001, 3002, 3003]),
            lookup: ProcessLookup(
                runner: SnapshotProcessRunner(),
                startTime: { _ in ProcessStartTime(seconds: 1, microseconds: 0) }
            )
        )
    }

    nonisolated private static func dockerPanelSnapshot() -> ServiceSnapshot {
        ServiceSnapshot(
            statuses: [
                ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
                ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .stopped),
                ServiceStatus(name: "Redis", detail: "Port 6379", state: .running)
            ],
            dockerContainerRows: [
                DockerContainerPortRow(
                    id: "container-web",
                    name: "web",
                    detail: "*:3000 -> 80/tcp"
                ),
                DockerContainerPortRow(
                    id: "container-api",
                    name: "api",
                    detail: "*:4000 -> 4000/tcp, localhost:9229 -> 9229/tcp"
                )
            ]
        )
    }

    nonisolated private static func densePanelSnapshot() -> ServiceSnapshot {
        ServiceSnapshot(statuses: [
            ServiceStatus(name: "Docker", detail: "Daemon", state: .running),
            ServiceStatus(name: "PostgreSQL", detail: "Port 5432", state: .running),
            ServiceStatus(name: "MySQL", detail: "Port 3306", state: .stopped),
            ServiceStatus(name: "Redis", detail: "Port 6379", state: .running),
            ServiceStatus(name: "MongoDB", detail: "Port 27017", state: .stopped)
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.start(showPanelOnLaunch: showPanelOnLaunch)
        guard let snapshotURL else { return }
        if snapshotKind == "settings" {
            menuBarController.viewModel.isShowingSettings = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [menuBarController, snapshotKind] in
            do {
                if snapshotKind == "panel-dense" {
                    let now = Date()
                    menuBarController.viewModel.recentPortChanges = (0..<4).map { offset in
                        PortChange(
                            port: UInt16(4000 + offset),
                            kind: .opened,
                            pid: 100 + offset,
                            processName: "node",
                            occurredAt: now
                        )
                    }
                }
                if snapshotKind == "button-states" {
                    try menuBarController.writeButtonInteractionSnapshot(to: snapshotURL)
                } else if snapshotKind == "settings" {
                    try menuBarController.writeSettingsSnapshot(to: snapshotURL)
                } else {
                    try menuBarController.writePanelSnapshot(to: snapshotURL)
                }
                NSApp.terminate(nil)
            } catch {
                fputs("PTK QA snapshot failed: \(error)\n", stderr)
                NSApp.terminate(nil)
            }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { [menuBarController] in
            await menuBarController.refreshNotificationPermissionStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController.stop()
        notificationClient?.stop()
    }
}

@MainActor
private final class SnapshotNotificationClient: PortChangeNotificationPermissionProviding, PortChangeNotificationDelivering {
    func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus { .unknown }
    func requestNotificationPermission() async throws {}
    func deliver(_ candidate: PortChangeNotificationCandidate) async throws {}
}
private struct SnapshotSocketConnector: SocketConnecting {
    let openPorts: Set<UInt16>

    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        openPorts.contains(port)
    }
}

private struct SnapshotProcessRunner: ProcessRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessRunResult {
        if executable == "lsof" {
            return ProcessRunResult(exitCode: 0, stdout: """
            COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
            node     3100 pgkim  20u  IPv4 0xabcd      0t0  TCP *:3000 (LISTEN)
            node     3101 pgkim  21u  IPv4 0xbcde      0t0  TCP *:3001 (LISTEN)
            node     3102 pgkim  22u  IPv4 0xcdef      0t0  TCP *:3002 (LISTEN)
            node     3103 pgkim  23u  IPv4 0xdef0      0t0  TCP *:3003 (LISTEN)
            vite     5173 pgkim  15u  IPv4 0xcdef      0t0  TCP 127.0.0.1:5173 (LISTEN)
            """)
        }
        if executable == "ps", arguments.count > 1,
           ["3100", "3101", "3102", "3103"].contains(arguments[1]) {
            return ProcessRunResult(exitCode: 0, stdout: "/usr/local/bin/node\n")
        }
        if executable == "ps", arguments == ["-p", "5173", "-o", "comm="] {
            return ProcessRunResult(exitCode: 0, stdout: "/usr/local/bin/vite\n")
        }
        return ProcessRunResult(exitCode: 1, stdout: "", stderr: "unsupported snapshot command")
    }
}

@MainActor
public func runPTKApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
