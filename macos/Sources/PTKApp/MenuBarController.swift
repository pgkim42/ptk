import AppKit
import PTKCore

@MainActor
final class MenuBarController: NSObject, @preconcurrency KillConfirming {
    private let settings: AppSettings
    private let parser: PortRangeParser
    private let scanner: PortScanner
    private let killService: KillService
    private var refreshScheduler: RefreshScheduler?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var statuses: [PortStatus] = []
    private var errorMessage: String?

    init(
        settings: AppSettings = AppSettings(),
        parser: PortRangeParser = PortRangeParser(),
        scanner: PortScanner = PortScanner(),
        killService: KillService = KillService()
    ) {
        self.settings = settings
        self.parser = parser
        self.scanner = scanner
        self.killService = killService
        super.init()
        self.refreshScheduler = RefreshScheduler(interval: settings.refreshInterval) { [weak self] in
            self?.performRefresh()
        }
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshScheduler?.triggerManualRefresh()
        scheduleRefreshTimer()
    }

    @objc private func refreshAction(_ sender: Any?) {
        refreshScheduler?.triggerManualRefresh()
    }

    @objc private func killPort(_ sender: NSMenuItem) {
        let coordinator = KillCoordinator(confirmer: self, service: killService)
        do {
            let outcome = try coordinator.requestKill(target: sender.representedObject as? KillTarget)
            if outcome == .terminated {
                refreshScheduler?.triggerManualRefresh()
            }
        } catch {
            showAlert(title: "종료 실패", message: "\(error)")
            refreshScheduler?.triggerManualRefresh()
        }
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Double,
              let interval = RefreshInterval(rawValue: rawValue) else {
            return
        }
        settings.refreshInterval = interval
        refreshScheduler?.changeInterval(to: interval)
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
        refreshScheduler?.triggerManualRefresh()
    }

    private func performRefresh() {
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
                let item = NSMenuItem(
                    title: row.canRequestKill ? "종료: \(row.displayText)" : row.displayText,
                    action: row.canRequestKill ? #selector(killPort(_:)) : nil,
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = row.killTarget
                item.isEnabled = row.canRequestKill
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

    func confirmKill(target: KillTarget) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "프로세스를 종료할까요?"
        alert.informativeText = "Port \(target.port), PID \(target.pid), \(target.processName)를 종료합니다."
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.runModal()
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
