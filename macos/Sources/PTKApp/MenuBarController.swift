import AppKit
import SwiftUI
import PTKCore

typealias PortScanWorker = @Sendable ([UInt16]) throws -> [PortStatus]
typealias ServiceSnapshotWorker = @Sendable ([DatabaseEndpoint]) throws -> ServiceSnapshot
typealias KillWorker = @Sendable (KillTarget) throws -> Void

enum KillRequestResult: Sendable {
    case settled(errorMessage: String?)
    case invalidated
}

struct ServiceStatusCompositionPolicy: Equatable, Sendable {
    let builtInDatabasePorts: Set<UInt16>

    init(defaultDatabaseEndpoints: [DatabaseEndpoint] = ServiceMonitor.defaultDatabaseEndpoints) {
        self.builtInDatabasePorts = Set(defaultDatabaseEndpoints.map(\.port))
    }

    func customEndpointsExcludingBuiltInPorts(_ endpoints: [DatabaseEndpoint]) -> [DatabaseEndpoint] {
        endpoints.filter { !builtInDatabasePorts.contains($0.port) }
    }

    func compose(defaultStatuses: [ServiceStatus], customStatuses: [ServiceStatus]) -> [ServiceStatus] {
        defaultStatuses + customStatuses
    }
}


@MainActor
final class MenuBarController: NSObject {
    private let settings: AppSettings
    private let parser: PortRangeParser
    private let portScanWorker: PortScanWorker
    private let serviceSnapshotWorker: ServiceSnapshotWorker
    private let killWorker: KillWorker
    private var refreshScheduler: RefreshScheduler?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private(set) lazy var viewModel: PortMonitorViewModel = makeViewModel()
    private var panel: NSPanel?
    private var hostingController: NSHostingController<ContentView>?
    private var statuses: [PortStatus] = []
    private var serviceStatuses: [ServiceStatus] = []
    private var dockerContainerRows: [DockerContainerPortRow] = []
    private var previousStatusesForChanges: [PortStatus]?
    private var recentPortChanges: [PortChange] = []
    private var portErrorMessage: String?
    private var serviceErrorMessage: String?
    private var nextGeneration = 0
    private var newestRequestedGeneration: Int?
    private var activeRefreshes: [Int: ActiveRefresh] = [:]
    private var pendingRefresh: RefreshRequest?
    private var killTask: Task<String?, Never>?
    private var activeKillID: UUID?
    private var isStopped = false
    private(set) var lastRefreshTriggerForTesting: RefreshTrigger?
    static let quietRefreshCadence: TimeInterval = 30

    private enum RefreshCadence {
        case normal
        case quiet
    }

    private var refreshCadence: RefreshCadence = .quiet

    private enum RefreshBranch: Hashable {
        case port
        case service
    }

    private struct RefreshRequest {
        let generation: Int
        let trigger: RefreshTrigger
        let completion: @MainActor () -> Void
    }

    private struct ActiveRefresh {
        let request: RefreshRequest
        var pendingBranches: Set<RefreshBranch>
        var portTask: Task<Void, Never>?
        var serviceTask: Task<Void, Never>?
    }

    private struct KillOperation {
        let id: UUID
        let task: Task<String?, Never>
    }

    var nextGenerationForTesting: Int {
        nextGeneration
    }

    var newestRequestedGenerationForTesting: Int? {
        newestRequestedGeneration
    }

    var activeGenerationsForTesting: [Int] {
        activeRefreshes.keys.sorted()
    }

    var pendingGenerationForTesting: Int? {
        pendingRefresh?.generation
    }

    func settlePortForTesting(generation: Int, statuses: [PortStatus]) {
        settlePortBranch(generation: generation, statuses: statuses)
    }

    func settlePortErrorForTesting(generation: Int, errorMessage: String) {
        settlePortBranch(generation: generation, errorMessage: errorMessage)
    }

    func settleServiceForTesting(generation: Int, snapshot: ServiceSnapshot) {
        settleServiceBranch(generation: generation, snapshot: snapshot)
    }

    func settleServiceErrorForTesting(generation: Int, errorMessage: String) {
        settleServiceBranch(generation: generation, errorMessage: errorMessage)
    }

    init(
        settings: AppSettings = AppSettings(),
        parser: PortRangeParser = PortRangeParser(),
        scanner: PortScanner = PortScanner(),
        serviceMonitor: ServiceMonitor = ServiceMonitor(),
        killService: KillService = KillService(),
        portScanWorker: PortScanWorker? = nil,
        serviceSnapshotWorker: ServiceSnapshotWorker? = nil,
        killWorker: KillWorker? = nil
    ) {
        self.settings = settings
        self.parser = parser
        self.portScanWorker = portScanWorker ?? { ports in
            scanner.scan(ports: ports)
        }
        self.killWorker = killWorker ?? { target in
            try killService.terminateAfterRevalidation(target: target)
        }

        let compositionPolicy = ServiceStatusCompositionPolicy()
        self.serviceSnapshotWorker = serviceSnapshotWorker ?? { customEndpoints in
            let defaultSnapshot = serviceMonitor.scanWithDetails()
            let filteredEndpoints = compositionPolicy.customEndpointsExcludingBuiltInPorts(customEndpoints)
            let customStatuses = filteredEndpoints.isEmpty
                ? []
                : ServiceMonitor(databaseEndpoints: filteredEndpoints).databaseStatuses(group: .custom)
            return ServiceSnapshot(
                statuses: compositionPolicy.compose(
                    defaultStatuses: defaultSnapshot.statuses,
                    customStatuses: customStatuses
                ),
                dockerContainerRows: defaultSnapshot.dockerContainerRows
            )
        }

        super.init()
        self.refreshScheduler = RefreshScheduler(interval: settings.refreshInterval) { [weak self] trigger, completion in
            guard let self else {
                completion()
                return
            }
            self.performRefresh(trigger: trigger, completion: completion)
        }
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    var currentRefreshTimerInterval: TimeInterval? {
        refreshTimer?.timeInterval
    }

    var activeRefreshCadenceSeconds: TimeInterval {
        switch refreshCadence {
        case .normal:
            settings.refreshInterval.rawValue
        case .quiet:
            Self.quietRefreshCadence
        }
    }

    func start(showPanelOnLaunch: Bool = false) {
        guard !isStopped else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.menu = nil
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        configureStatusButton()

        setupPanel()
        refreshScheduler?.triggerStartupRefresh()
        scheduleRefreshTimer()

        if showPanelOnLaunch {
            showPanelForAutomation()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        refreshScheduler?.stop()

        let refreshes = Array(activeRefreshes.values)
        newestRequestedGeneration = nil
        pendingRefresh = nil
        activeRefreshes.removeAll()
        for refresh in refreshes {
            refresh.portTask?.cancel()
            refresh.serviceTask?.cancel()
        }
        killTask?.cancel()
        killTask = nil
        activeKillID = nil
        viewModel.cancelActiveWork()
        viewModel.isRefreshing = false

        refreshTimer?.invalidate()
        refreshTimer = nil
        (panel as? PTKPanel)?.onOrderOut = nil
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
        let fittingSize = hosting.sizeThatFits(in: NSSize(width: 320, height: 520))
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
            parser: parser,
            onRefresh: { [weak self] in
                self?.refreshScheduler?.triggerManualRefresh()
            },
            onSettingsRefresh: { [weak self] in
                self?.refreshScheduler?.triggerSettingsRefresh()
            },
            onKill: { [weak self] target in
                guard let operation = self?.beginKill(target) else { return .invalidated }
                let errorMessage = await operation.task.value
                guard let self else { return .invalidated }
                return self.finishKill(operationID: operation.id, errorMessage: errorMessage)
            },
            onKillSettled: { [weak self] in
                self?.refreshScheduler?.triggerKillRefresh()
            },
            onIntervalChange: { [weak self] interval in
                self?.refreshScheduler?.changeInterval(to: interval)
                self?.applyCurrentPanelCadence()
                self?.refreshScheduler?.triggerSettingsRefresh()
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
        utilityPanel.onOrderOut = { [weak self] in
            self?.applyQuietCadence()
        }
        panel = utilityPanel
    }

    private func configureStatusButton() {
        guard let button = statusItem?.button else { return }
        let content = viewModel.menuBarStatusContent
        button.title = content.countText
        button.image = NSImage(
            systemSymbolName: content.symbolName,
            accessibilityDescription: content.accessibilityLabel
        )
        button.image?.isTemplate = true
        button.image?.setName(NSImage.Name(content.symbolName))
        button.imagePosition = .imageLeading
        button.toolTip = content.toolTip
        button.setAccessibilityLabel(content.accessibilityLabel)
    }

    var menuBarButtonStateForTesting: MenuBarButtonState? {
        guard let button = statusItem?.button else { return nil }
        return MenuBarButtonState(
            title: button.title,
            hasImage: button.image != nil,
            toolTip: button.toolTip,
            accessibilityLabel: button.accessibilityLabel()
        )
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
        applyNormalCadence(triggerRefresh: true)
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
        applyNormalCadence(triggerRefresh: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: activeRefreshCadenceSeconds,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func applyPanelClosedForTesting() {
        applyQuietCadence()
    }

    func applyPanelOpenedForTesting() {
        applyNormalCadence(triggerRefresh: true)
    }

    private func applyCurrentPanelCadence() {
        if isPanelVisible {
            applyNormalCadence(triggerRefresh: false)
        } else {
            applyQuietCadence()
        }
    }

    private func applyNormalCadence(triggerRefresh: Bool) {
        refreshCadence = .normal
        scheduleRefreshTimer()
        if triggerRefresh {
            refreshScheduler?.triggerManualRefresh()
        }
    }

    private func applyQuietCadence() {
        refreshCadence = .quiet
        scheduleRefreshTimer()
    }

    @objc private func timerFired(_ timer: Timer) {
        refreshScheduler?.triggerTimerRefresh()
    }

    func fireTimerForTesting() {
        refreshScheduler?.triggerTimerRefresh()
    }

    func performRefresh() {
        refreshScheduler?.triggerManualRefresh()
    }

    private func performRefresh(
        trigger: RefreshTrigger,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !isStopped else {
            completion()
            return
        }

        nextGeneration += 1
        let request = RefreshRequest(
            generation: nextGeneration,
            trigger: trigger,
            completion: completion
        )
        newestRequestedGeneration = request.generation
        lastRefreshTriggerForTesting = trigger

        if activeRefreshes.count < 2 {
            startRefresh(request)
        } else {
            let replacedRequest = pendingRefresh
            pendingRefresh = request
            updateRefreshProgress()
            replacedRequest?.completion()
        }
    }

    private func startRefresh(_ request: RefreshRequest) {
        guard !isStopped, activeRefreshes.count < 2 else { return }

        activeRefreshes[request.generation] = ActiveRefresh(
            request: request,
            pendingBranches: [.port, .service],
            portTask: nil,
            serviceTask: nil
        )
        updateRefreshProgress()

        let generation = request.generation
        let customEndpoints = settings.customServiceEndpoints
        let serviceSnapshotWorker = serviceSnapshotWorker
        let serviceTask = Task.detached(priority: .utility) { [weak self, customEndpoints, serviceSnapshotWorker] in
            guard self != nil, !Task.isCancelled else { return }
            do {
                let snapshot = try serviceSnapshotWorker(customEndpoints)
                await self?.settleServiceBranch(generation: generation, snapshot: snapshot)
            } catch {
                await self?.settleServiceBranch(generation: generation, errorMessage: "\(error)")
            }
        }
        setTask(serviceTask, branch: .service, generation: generation)

        let expression = settings.watchedPortsExpression
        let ports: [UInt16]
        do {
            ports = try parser.parse(expression)
        } catch {
            settlePortBranch(
                generation: generation,
                errorMessage: "포트 설정 오류: \(error)"
            )
            return
        }

        let portScanWorker = portScanWorker
        let portTask = Task.detached(priority: .utility) { [weak self, ports, portScanWorker] in
            guard self != nil, !Task.isCancelled else { return }
            do {
                let statuses = try portScanWorker(ports)
                await self?.settlePortBranch(generation: generation, statuses: statuses)
            } catch {
                await self?.settlePortBranch(generation: generation, errorMessage: "\(error)")
            }
        }
        setTask(portTask, branch: .port, generation: generation)
    }

    private func setTask(
        _ task: Task<Void, Never>,
        branch: RefreshBranch,
        generation: Int
    ) {
        guard var refresh = activeRefreshes[generation] else {
            task.cancel()
            return
        }
        switch branch {
        case .port:
            refresh.portTask = task
        case .service:
            refresh.serviceTask = task
        }
        activeRefreshes[generation] = refresh
    }

    private func settlePortBranch(generation: Int, statuses: [PortStatus]) {
        guard canSettle(generation: generation, branch: .port) else { return }
        if canPublish(generation: generation) {
            trackPortChanges(statuses)
            self.statuses = statuses
            portErrorMessage = statuses.compactMap(\.message).first
            updateViewModel()
        }
        settle(generation: generation, branch: .port)
    }

    private func settlePortBranch(generation: Int, errorMessage: String) {
        guard canSettle(generation: generation, branch: .port) else { return }
        if canPublish(generation: generation) {
            portErrorMessage = errorMessage
            updateViewModel()
        }
        settle(generation: generation, branch: .port)
    }

    private func settleServiceBranch(generation: Int, snapshot: ServiceSnapshot) {
        guard canSettle(generation: generation, branch: .service) else { return }
        if canPublish(generation: generation) {
            serviceStatuses = snapshot.statuses
            dockerContainerRows = snapshot.dockerContainerRows
            serviceErrorMessage = nil
            updateViewModel()
        }
        settle(generation: generation, branch: .service)
    }

    private func settleServiceBranch(generation: Int, errorMessage: String) {
        guard canSettle(generation: generation, branch: .service) else { return }
        if canPublish(generation: generation) {
            serviceErrorMessage = errorMessage
            updateViewModel()
        }
        settle(generation: generation, branch: .service)
    }

    private func canSettle(generation: Int, branch: RefreshBranch) -> Bool {
        guard !isStopped, let refresh = activeRefreshes[generation] else { return false }
        return refresh.pendingBranches.contains(branch)
    }

    private func canPublish(generation: Int) -> Bool {
        !isStopped && newestRequestedGeneration == generation
    }

    private func settle(generation: Int, branch: RefreshBranch) {
        guard var refresh = activeRefreshes[generation] else { return }
        guard refresh.pendingBranches.remove(branch) != nil else { return }

        switch branch {
        case .port:
            refresh.portTask = nil
        case .service:
            refresh.serviceTask = nil
        }

        guard refresh.pendingBranches.isEmpty else {
            activeRefreshes[generation] = refresh
            updateRefreshProgress()
            return
        }

        activeRefreshes.removeValue(forKey: generation)
        refresh.request.completion()

        if !isStopped, activeRefreshes.count < 2, let request = pendingRefresh {
            pendingRefresh = nil
            startRefresh(request)
        }
        updateRefreshProgress()
    }

    private func updateRefreshProgress() {
        guard !isStopped, let newestRequestedGeneration else {
            viewModel.isRefreshing = false
            return
        }
        if pendingRefresh?.generation == newestRequestedGeneration {
            viewModel.isRefreshing = true
            return
        }
        viewModel.isRefreshing =
            activeRefreshes[newestRequestedGeneration]?.pendingBranches.isEmpty == false
    }

    private func beginKill(_ target: KillTarget) -> KillOperation? {
        guard !isStopped, activeKillID == nil else { return nil }

        let killID = UUID()
        activeKillID = killID
        let killWorker = killWorker
        let task = Task<String?, Never>.detached(priority: .userInitiated) { [killWorker, target] in
            guard !Task.isCancelled else { return nil }
            do {
                try killWorker(target)
                return nil
            } catch {
                return "\(error)"
            }
        }
        killTask = task
        return KillOperation(id: killID, task: task)
    }

    private func finishKill(operationID: UUID, errorMessage: String?) -> KillRequestResult {
        guard !isStopped, activeKillID == operationID else { return .invalidated }

        activeKillID = nil
        killTask = nil
        return .settled(errorMessage: errorMessage)
    }

    private func trackPortChanges(_ scannedStatuses: [PortStatus]) {
        if let previousStatusesForChanges {
            let occurredAt = Date()
            let changes = PortChange.detect(
                previous: previousStatusesForChanges,
                current: scannedStatuses,
                occurredAt: occurredAt
            )
            if !changes.isEmpty {
                recentPortChanges = Array((changes + recentPortChanges).prefix(4))
            }
        }
        previousStatusesForChanges = scannedStatuses
    }

    private func updateViewModel() {
        viewModel.statuses = statuses
        viewModel.serviceStatuses = serviceStatuses
        viewModel.dockerContainerRows = dockerContainerRows
        viewModel.recentPortChanges = recentPortChanges
        viewModel.errorMessage = [portErrorMessage, serviceErrorMessage]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty
        configureStatusButton()
    }
}

private final class PTKPanel: NSPanel {
    var onOrderOut: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onOrderOut?()
    }
}

struct MenuBarButtonState: Equatable {
    let title: String
    let hasImage: Bool
    let toolTip: String?
    let accessibilityLabel: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
