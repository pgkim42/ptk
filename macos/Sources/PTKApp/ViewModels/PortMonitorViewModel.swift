import SwiftUI
import PTKCore

@MainActor
final class PortMonitorViewModel: ObservableObject {
    @Published var statuses: [PortStatus] = []
    @Published var serviceStatuses: [ServiceStatus] = []
    @Published var errorMessage: String?

    @Published var portExpression: String
    @Published var refreshInterval: RefreshInterval
    @Published var theme: AppTheme

    @Published var killConfirmationTarget: KillTarget?
    @Published var killErrorMessage: String?
    @Published var isShowingSettings = false

    var menuBarTitle: String {
        "\(AppDefaults.appName) \(statuses.filter(\.isOpen).count)"
    }

    var openPorts: [PortStatus] {
        statuses.filter(\.isOpen).sorted { $0.port < $1.port }
    }

    var hasError: Bool { errorMessage != nil }

    private let settings: AppSettings
    private let killService: KillService
    private let parser: PortRangeParser
    private let onRefresh: () -> Void
    private let onIntervalChange: (RefreshInterval) -> Void

    init(
        settings: AppSettings,
        killService: KillService = KillService(),
        parser: PortRangeParser = PortRangeParser(),
        onRefresh: @escaping () -> Void,
        onIntervalChange: @escaping (RefreshInterval) -> Void = { _ in }
    ) {
        self.settings = settings
        self.killService = killService
        self.parser = parser
        self.portExpression = settings.watchedPortsExpression
        self.refreshInterval = settings.refreshInterval
        self.theme = settings.theme
        self.onRefresh = onRefresh
        self.onIntervalChange = onIntervalChange
    }

    func refresh() {
        onRefresh()
    }

    func requestKill(_ target: KillTarget) {
        killConfirmationTarget = target
        killErrorMessage = nil
    }

    func confirmKill() {
        guard let target = killConfirmationTarget else { return }
        killConfirmationTarget = nil
        do {
            try killService.terminateAfterRevalidation(target: target)
        } catch {
            killErrorMessage = "\(error)"
        }
        onRefresh()
    }

    func cancelKill() {
        killConfirmationTarget = nil
    }

    func saveExpression(_ expression: String) throws {
        try settings.updateWatchedPortsExpression(expression, parser: parser)
        portExpression = expression
        onRefresh()
    }

    func saveInterval(_ interval: RefreshInterval) {
        settings.refreshInterval = interval
        refreshInterval = interval
        onIntervalChange(interval)
    }

    func saveTheme(_ theme: AppTheme) {
        settings.theme = theme
        self.theme = theme
    }
}
