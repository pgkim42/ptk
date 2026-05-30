import AppKit
import PTKCore

typealias ServiceStatusLoader = (@escaping @MainActor ([ServiceStatus]) -> Void) -> Void

private final class DefaultServiceStatusLoader: @unchecked Sendable {
    private let serviceMonitor: ServiceMonitor

    init(serviceMonitor: ServiceMonitor) {
        self.serviceMonitor = serviceMonitor
    }

    func load(completion: @escaping @MainActor ([ServiceStatus]) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let statuses = serviceMonitor.scan()
            Task { @MainActor in
                completion(statuses)
            }
        }
    }
}

@MainActor
final class MenuBarController: NSObject, @preconcurrency KillConfirming {
    private let settings: AppSettings
    private let parser: PortRangeParser
    private let scanner: PortScanner
    private let killService: KillService
    private let serviceStatusLoader: ServiceStatusLoader
    private var refreshScheduler: RefreshScheduler?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var statuses: [PortStatus] = []
    private var serviceStatuses: [ServiceStatus] = []
    private var errorMessage: String?

    init(
        settings: AppSettings = AppSettings(),
        parser: PortRangeParser = PortRangeParser(),
        scanner: PortScanner = PortScanner(),
        serviceMonitor: ServiceMonitor = ServiceMonitor(),
        killService: KillService = KillService(),
        serviceStatusLoader: ServiceStatusLoader? = nil
    ) {
        self.settings = settings
        self.parser = parser
        self.scanner = scanner
        self.killService = killService
        let defaultServiceStatusLoader = DefaultServiceStatusLoader(serviceMonitor: serviceMonitor)
        self.serviceStatusLoader = serviceStatusLoader ?? defaultServiceStatusLoader.load(completion:)
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

    @objc func refreshAction(_ sender: Any?) {
        refreshScheduler?.triggerManualRefresh()
    }

    @objc func editWatchedPorts(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "감시 포트 설정"
        alert.informativeText = "감시할 포트 또는 범위를 입력하세요. 예: 3000-3009,5173"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(string: settings.watchedPortsExpression)
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try settings.updateWatchedPortsExpression(input.stringValue, parser: parser)
            refreshScheduler?.triggerManualRefresh()
        } catch {
            showAlert(title: "포트 설정 오류", message: "\(error)")
        }
    }

    @objc func killPort(_ sender: NSMenuItem) {
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

    @objc func selectInterval(_ sender: NSMenuItem) {
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

    func performRefresh() {
        loadServiceStatuses()
        do {
            let ports = try parser.parse(settings.watchedPortsExpression)
            statuses = scanner.scan(ports: ports)
            errorMessage = statuses.compactMap(\.message).first
        } catch {
            errorMessage = "포트 설정 오류: \(error)"
        }
        rebuildMenu()
    }

    private func loadServiceStatuses() {
        serviceStatusLoader { [weak self] statuses in
            self?.serviceStatuses = statuses
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let model = MenuModel(
            statuses: statuses,
            selectedRefreshInterval: settings.refreshInterval,
            errorMessage: errorMessage
        )
        statusItem?.button?.title = model.title

        let builder = MenuBarMenuBuilder(target: self)
        statusItem?.menu = builder.menu(model: model, serviceStatuses: serviceStatuses)
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

    func refreshIntervalMenuItem(model: MenuModel) -> NSMenuItem {
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

@MainActor
struct MenuBarMenuBuilder {
    let target: MenuBarController

    func menu(model: MenuModel, serviceStatuses: [ServiceStatus]) -> NSMenu {
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
                    action: row.canRequestKill ? #selector(MenuBarController.killPort(_:)) : nil,
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = row.killTarget
                item.isEnabled = row.canRequestKill
                menu.addItem(item)
            }
        }

        let serviceItems = serviceMenuItems(statuses: serviceStatuses)
        if !serviceItems.isEmpty {
            menu.addItem(.separator())
            for item in serviceItems {
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        for item in controlMenuItems(model: model) {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func controlMenuItems(model: MenuModel) -> [NSMenuItem] {
        let refreshItem = NSMenuItem(title: "새로고침", action: #selector(MenuBarController.refreshAction(_:)), keyEquivalent: "r")
        refreshItem.target = target

        let watchedPortsItem = NSMenuItem(title: "감시 포트 설정...", action: #selector(MenuBarController.editWatchedPorts(_:)), keyEquivalent: "")
        watchedPortsItem.target = target

        return [refreshItem, watchedPortsItem, target.refreshIntervalMenuItem(model: model)]
    }

    func serviceMenuItems(statuses: [ServiceStatus]) -> [NSMenuItem] {
        guard !statuses.isEmpty else { return [] }

        let titleItem = NSMenuItem(title: "서비스 상태", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false

        return [titleItem] + statuses.map { status in
            let item = NSMenuItem(title: status.displayText, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
    }
}
