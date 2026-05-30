import AppKit
import PTKCore

@MainActor
final class MenuBarController: NSObject {
    private let settings: AppSettings
    private let parser: PortRangeParser
    private let scanner: PortScanner
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var statuses: [PortStatus] = []
    private var errorMessage: String?

    init(
        settings: AppSettings = AppSettings(),
        parser: PortRangeParser = PortRangeParser(),
        scanner: PortScanner = PortScanner()
    ) {
        self.settings = settings
        self.parser = parser
        self.scanner = scanner
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshNow()
        scheduleRefreshTimer()
    }

    @objc private func refreshAction(_ sender: Any?) {
        refreshNow()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Double,
              let interval = RefreshInterval(rawValue: rawValue) else {
            return
        }
        settings.refreshInterval = interval
        scheduleRefreshTimer()
        rebuildMenu()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: settings.refreshInterval.rawValue,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerFired(_ timer: Timer) {
        refreshNow()
    }

    private func refreshNow() {
        do {
            let ports = try parser.parse(settings.watchedPortsExpression)
            statuses = scanner.scan(ports: ports)
            errorMessage = statuses.compactMap(\.message).first
        } catch {
            errorMessage = "포트 설정 오류: \(error)"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let model = MenuModel(
            statuses: statuses,
            selectedRefreshInterval: settings.refreshInterval,
            errorMessage: errorMessage
        )
        statusItem?.button?.title = model.title

        let menu = NSMenu()
        if let errorMessage = model.errorMessage {
            let errorItem = NSMenuItem(title: errorMessage, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            menu.addItem(.separator())
        }

        if model.rows.isEmpty {
            let emptyItem = NSMenuItem(title: "열린 감시 포트 없음", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for row in model.rows {
                let item = NSMenuItem(title: row.displayText, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "새로고침", action: #selector(refreshAction(_:)), keyEquivalent: "r"))
        menu.addItem(refreshIntervalMenuItem(model: model))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func refreshIntervalMenuItem(model: MenuModel) -> NSMenuItem {
        let item = NSMenuItem(title: "새로고침 주기", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "새로고침 주기")

        for interval in model.refreshIntervals {
            let intervalItem = NSMenuItem(
                title: interval.label,
                action: #selector(selectInterval(_:)),
                keyEquivalent: ""
            )
            intervalItem.target = self
            intervalItem.representedObject = interval.rawValue
            intervalItem.state = interval == model.selectedRefreshInterval ? .on : .off
            submenu.addItem(intervalItem)
        }

        item.submenu = submenu
        return item
    }
}
