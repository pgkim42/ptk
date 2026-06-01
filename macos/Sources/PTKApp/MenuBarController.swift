import AppKit
import SwiftUI
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
final class MenuBarController: NSObject {
    private let settings: AppSettings
    private let parser: PortRangeParser
    private let scanner: PortScanner
    private let killService: KillService
    private let serviceStatusLoader: ServiceStatusLoader
    private var refreshScheduler: RefreshScheduler?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private(set) lazy var viewModel: PortMonitorViewModel = makeViewModel()
    private var panel: NSPanel?
    private var hostingController: NSHostingController<ContentView>?
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
        item.menu = nil
        item.button?.action = #selector(togglePopover)
        item.button?.target = self

        setupPanel()
        refreshScheduler?.triggerManualRefresh()
        scheduleRefreshTimer()
    }

    private func makeViewModel() -> PortMonitorViewModel {
        PortMonitorViewModel(
            settings: settings,
            killService: killService,
            parser: parser,
            onRefresh: { [weak self] in
                self?.refreshScheduler?.triggerManualRefresh()
            },
            onIntervalChange: { [weak self] interval in
                self?.refreshScheduler?.changeInterval(to: interval)
                self?.scheduleRefreshTimer()
            }
        )
    }

    private func setupPanel() {
        let contentView = ContentView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: contentView)
        hosting.view.frame = NSRect(origin: .zero, size: ContentView.panelSize)
        hostingController = hosting

        let utilityPanel = PTKPanel(
            contentRect: NSRect(origin: .zero, size: ContentView.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        utilityPanel.contentViewController = hosting
        utilityPanel.backgroundColor = .clear
        utilityPanel.isOpaque = false
        utilityPanel.hasShadow = true
        utilityPanel.hidesOnDeactivate = true
        utilityPanel.isReleasedWhenClosed = false
        utilityPanel.level = .floating
        utilityPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = utilityPanel
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if panel?.isVisible == true {
            panel?.orderOut(sender)
        } else {
            showPanel(relativeTo: button)
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let window = button.window, let panel else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = window.convertToScreen(buttonFrameInWindow)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let panelSize = ContentView.panelSize

        let centeredX = buttonFrame.midX - panelSize.width / 2
        let x = min(max(centeredX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let y = buttonFrame.minY - panelSize.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, visibleFrame.minY + 8)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        updateViewModel()
    }

    private func loadServiceStatuses() {
        serviceStatusLoader { [weak self] statuses in
            guard let self else { return }
            self.serviceStatuses = statuses
            self.updateViewModel()
        }
    }

    private func updateViewModel() {
        viewModel.statuses = statuses
        viewModel.serviceStatuses = serviceStatuses
        viewModel.errorMessage = errorMessage
        statusItem?.button?.title = viewModel.menuBarTitle
    }
}

private final class PTKPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
