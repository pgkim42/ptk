import AppKit
import PTKCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController: MenuBarController
    private let showPanelOnLaunch: Bool
    private let snapshotURL: URL?
    private let snapshotKind: String

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let snapshotURL = environment["PTK_QA_SNAPSHOT_PATH"].map(URL.init(fileURLWithPath:))
        let snapshotKind = environment["PTK_QA_SNAPSHOT_KIND"] ?? "panel"
        let settings = snapshotURL == nil
            ? AppSettings()
            : AppSettings(store: InMemorySettingsStore())
        if let rawTheme = environment["PTK_QA_THEME"], let theme = AppTheme(rawValue: rawTheme) {
            settings.theme = theme
        }
        if snapshotKind == "panel-docker" {
            settings.watchedPortsExpression = "3000-3009,5173-5182,4200-4209,8080-8089"
        }
        self.snapshotURL = snapshotURL
        self.snapshotKind = snapshotKind
        showPanelOnLaunch = environment["PTK_QA_SHOW_PANEL"] == "1" || snapshotURL != nil
        let scanner: PortScanner
        let serviceSnapshotWorker: ServiceSnapshotWorker?
        if snapshotKind == "panel-docker" {
            scanner = Self.dockerPanelSnapshotScanner
            serviceSnapshotWorker = { _ in Self.dockerPanelSnapshot() }
        } else {
            scanner = PortScanner()
            serviceSnapshotWorker = nil
        }
        menuBarController = MenuBarController(
            settings: settings,
            scanner: scanner,
            serviceSnapshotWorker: serviceSnapshotWorker
        )
        super.init()
    }

    private static var dockerPanelSnapshotScanner: PortScanner {
        PortScanner(
            connector: SnapshotSocketConnector(openPorts: [3000, 5173]),
            lookup: ProcessLookup(runner: SnapshotProcessRunner())
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
                    detail: "3000 -> 80"
                ),
                DockerContainerPortRow(
                    id: "container-api",
                    name: "api",
                    detail: "4000 -> 4000, 9229 -> 9229"
                )
            ]
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.start(showPanelOnLaunch: showPanelOnLaunch)
        guard let snapshotURL else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [menuBarController, snapshotKind] in
            do {
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
            vite     5173 pgkim  15u  IPv4 0xcdef      0t0  TCP 127.0.0.1:5173 (LISTEN)
            """)
        }
        if executable == "ps", arguments == ["-p", "3100", "-o", "comm="] {
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
