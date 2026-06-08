import Foundation
import SwiftUI
import PTKCore

@MainActor
final class PortMonitorViewModel: ObservableObject {
    @Published var statuses: [PortStatus] = []
    @Published var serviceStatuses: [ServiceStatus] = []
    @Published var recentPortChanges: [PortChange] = []
    @Published var errorMessage: String?

    @Published var portExpression: String
    @Published var refreshInterval: RefreshInterval
    @Published var theme: AppTheme
    @Published var customPortProfiles: [PortProfile]
    @Published var customServiceEndpoints: [DatabaseEndpoint]

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
    private let onOpenLocalhost: (URL) -> Void
    private let onCopyText: (String) -> Void

    init(
        settings: AppSettings,
        killService: KillService = KillService(),
        parser: PortRangeParser = PortRangeParser(),
        onRefresh: @escaping () -> Void,
        onIntervalChange: @escaping (RefreshInterval) -> Void = { _ in },
        onOpenLocalhost: @escaping (URL) -> Void = { _ in },
        onCopyText: @escaping (String) -> Void = { _ in }
    ) {
        self.settings = settings
        self.killService = killService
        self.parser = parser
        self.portExpression = settings.watchedPortsExpression
        self.refreshInterval = settings.refreshInterval
        self.theme = settings.theme
        self.customPortProfiles = settings.customPortProfiles
        self.customServiceEndpoints = settings.customServiceEndpoints
        self.onRefresh = onRefresh
        self.onIntervalChange = onIntervalChange
        self.onOpenLocalhost = onOpenLocalhost
        self.onCopyText = onCopyText
    }

    var portPresets: [PortPreset] {
        AppDefaults.portPresets
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

    func applyPreset(_ preset: PortPreset) throws {
        try saveExpression(preset.expression)
    }

    func applyProfile(_ profile: PortProfile) throws {
        try saveExpression(profile.expression)
    }

    func saveCustomProfile(title: String, expression: String) throws {
        try settings.saveCustomPortProfile(title: title, expression: expression, parser: parser)
        customPortProfiles = settings.customPortProfiles
    }

    func deleteCustomProfile(_ profile: PortProfile) {
        settings.deleteCustomPortProfile(id: profile.id)
        customPortProfiles = settings.customPortProfiles
    }

    func saveCustomServiceEndpoint(name: String, portText: String) throws {
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AppSettingsError.invalidServicePort
        }
        try settings.saveCustomServiceEndpoint(name: name, port: port)
        customServiceEndpoints = settings.customServiceEndpoints
        onRefresh()
    }

    func deleteCustomServiceEndpoint(_ endpoint: DatabaseEndpoint) {
        settings.deleteCustomServiceEndpoint(id: endpoint.id)
        customServiceEndpoints = settings.customServiceEndpoints
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

    func openLocalhost(for status: PortStatus) {
        onOpenLocalhost(localhostURL(for: status.port))
    }

    func copyLocalhostURL(for status: PortStatus) {
        onCopyText(localhostURL(for: status.port).absoluteString)
    }

    func copyPortDetails(for status: PortStatus) {
        var lines = [
            "Port: \(status.port)",
            "URL: \(localhostURL(for: status.port).absoluteString)"
        ]
        if let pid = status.pid {
            lines.append("PID: \(pid)")
        }
        if let processName = status.processName, !processName.isEmpty {
            lines.append("Process: \(processName)")
        }
        if let reason = status.killUnavailableReason {
            lines.append("Kill unavailable: \(reason)")
        }
        onCopyText(lines.joined(separator: "\n"))
    }

    func copyOpenPortsSummary() {
        guard !openPorts.isEmpty else {
            onCopyText("No open watched ports")
            return
        }

        let summary = openPorts.map { status in
            var parts = ["\(status.port)"]
            if let processName = status.processName, !processName.isEmpty {
                parts.append(processName)
            }
            if let pid = status.pid {
                parts.append("PID \(pid)")
            }
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
        onCopyText(summary)
    }

    private func localhostURL(for port: UInt16) -> URL {
        URL(string: "http://localhost:\(port)")!
    }
}
