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
        let settings = snapshotURL == nil
            ? AppSettings()
            : AppSettings(store: InMemorySettingsStore())
        if let rawTheme = environment["PTK_QA_THEME"], let theme = AppTheme(rawValue: rawTheme) {
            settings.theme = theme
        }
        self.snapshotURL = snapshotURL
        snapshotKind = environment["PTK_QA_SNAPSHOT_KIND"] ?? "panel"
        showPanelOnLaunch = environment["PTK_QA_SHOW_PANEL"] == "1" || snapshotURL != nil
        menuBarController = MenuBarController(settings: settings)
        super.init()
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

@MainActor
public func runPTKApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
