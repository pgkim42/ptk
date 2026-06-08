import AppKit
import SwiftUI
import PTKCore

typealias ServiceStatusLoader = (@escaping @MainActor ([ServiceStatus]) -> Void) -> Void

private final class DefaultServiceStatusLoader: @unchecked Sendable {
    private let serviceMonitor: ServiceMonitor
    private let customEndpoints: () -> [DatabaseEndpoint]

    init(
        serviceMonitor: ServiceMonitor,
        customEndpoints: @escaping () -> [DatabaseEndpoint] = { [] }
    ) {
        self.serviceMonitor = serviceMonitor
        self.customEndpoints = customEndpoints
    }

    func load(completion: @escaping @MainActor ([ServiceStatus]) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let defaultStatuses = serviceMonitor.scan()
            let defaultPorts = Set(ServiceMonitor.defaultDatabaseEndpoints.map(\.port))
            let customEndpoints = customEndpoints().filter { !defaultPorts.contains($0.port) }
            let customStatuses = customEndpoints.isEmpty
                ? []
                : ServiceMonitor(databaseEndpoints: customEndpoints).databaseStatuses()
            let statuses = defaultStatuses + customStatuses
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
    private var previousStatusesForChanges: [PortStatus]?
    private var recentPortChanges: [PortChange] = []
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
        let defaultServiceStatusLoader = DefaultServiceStatusLoader(
            serviceMonitor: serviceMonitor,
            customEndpoints: { settings.customServiceEndpoints }
        )
        self.serviceStatusLoader = serviceStatusLoader ?? defaultServiceStatusLoader.load(completion:)
        super.init()
        self.refreshScheduler = RefreshScheduler(interval: settings.refreshInterval) { [weak self] in
            self?.performRefresh()
        }
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    func start(showPanelOnLaunch: Bool = false) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.menu = nil
        item.button?.action = #selector(togglePopover)
        item.button?.target = self

        setupPanel()
        refreshScheduler?.triggerManualRefresh()
        scheduleRefreshTimer()

        if showPanelOnLaunch {
            showPanelForAutomation()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func writePanelSnapshot(to url: URL) throws {
        guard let view = hostingController?.view else {
            throw CocoaError(.fileNoSuchFile)
        }
        try writeSnapshot(of: view, to: url)
    }

    func writeSettingsSnapshot(to url: URL) throws {
        let hosting = NSHostingController(rootView: SettingsSheetView(viewModel: viewModel, onDismiss: {}))
        let fittingSize = hosting.sizeThatFits(in: NSSize(width: 320, height: 360))
        hosting.view.frame = NSRect(
            origin: .zero,
            size: NSSize(width: 320, height: max(fittingSize.height, 180))
        )
        try writeSnapshot(of: hosting.view, to: url)
    }

    func writeButtonInteractionSnapshot(to url: URL) throws {
        let hosting = NSHostingController(
            rootView: PTKButtonInteractionPreview()
                .preferredColorScheme(viewModel.theme.preferredColorScheme)
        )
        let fittingSize = hosting.sizeThatFits(in: NSSize(width: 260, height: 120))
        hosting.view.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(fittingSize.width, 200), height: max(fittingSize.height, 90))
        )
        try writeSnapshot(of: hosting.view, to: url)
    }

    private func writeSnapshot(of view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
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
            },
            onOpenLocalhost: { url in
                NSWorkspace.shared.open(url)
            },
            onCopyText: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
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
        utilityPanel.sharingType = .readOnly
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

    private func showPanelForAutomation() {
        guard let panel else { return }
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let panelSize = ContentView.panelSize
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.midY - panelSize.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
            let scannedStatuses = scanner.scan(ports: ports)
            trackPortChanges(scannedStatuses)
            statuses = scannedStatuses
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

    private func trackPortChanges(_ scannedStatuses: [PortStatus]) {
        if let previousStatusesForChanges {
            let changes = PortChange.detect(previous: previousStatusesForChanges, current: scannedStatuses)
            if !changes.isEmpty {
                recentPortChanges = Array((changes + recentPortChanges).prefix(4))
            }
        }
        previousStatusesForChanges = scannedStatuses
    }

    private func updateViewModel() {
        viewModel.statuses = statuses
        viewModel.serviceStatuses = serviceStatuses
        viewModel.recentPortChanges = recentPortChanges
        viewModel.errorMessage = errorMessage
        statusItem?.button?.title = viewModel.menuBarTitle
    }
}

private final class PTKPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
