import Foundation
import SwiftUI
import PTKCore

struct PortProfileOption: Equatable, Identifiable {
    let id: String
    let title: String
    let expression: String
}

struct ServiceStatusGroup: Equatable, Identifiable {
    let id: ServiceGroup
    let title: String
    let statuses: [ServiceStatus]
}
struct KillUnavailableDiagnostic: Equatable, Sendable {
    let title: String
    let detail: String?
    let hint: String
}

struct KillUnavailableDiagnosticPresenter {
    func diagnostic(for status: PortStatus) -> KillUnavailableDiagnostic? {
        guard let cause = status.killUnavailableCause else { return nil }
        switch cause {
        case let .ambiguousListener(message):
            return KillUnavailableDiagnostic(
                title: "여러 listener가 있어 안전하게 종료할 수 없음",
                detail: message,
                hint: "포트 \(status.port)를 점유한 프로세스를 터미널에서 직접 확인한 뒤 정리하세요."
            )
        case let .lookupFailed(message):
            return KillUnavailableDiagnostic(
                title: "프로세스 조회 실패로 안전하게 종료할 수 없음",
                detail: message,
                hint: "새로고침 후에도 반복되면 lsof/ps 결과를 확인하세요."
            )
        case .missingPID:
            return KillUnavailableDiagnostic(
                title: "PID를 찾을 수 없어 안전하게 종료할 수 없음",
                detail: nil,
                hint: "프로세스 조회 권한 또는 포트 상태를 확인한 뒤 다시 새로고침하세요."
            )
        case let .missingProcessName(pid):
            return KillUnavailableDiagnostic(
                title: "프로세스 이름을 확인할 수 없어 안전하게 종료할 수 없음",
                detail: nil,
                hint: "PID \(pid)의 프로세스가 바뀌었을 수 있으니 다시 새로고침하세요."
            )
        }
    }
}

extension PortStatus {
    var ptkKillUnavailableDiagnostic: KillUnavailableDiagnostic? {
        KillUnavailableDiagnosticPresenter().diagnostic(for: self)
    }

    var ptkKillUnavailableReason: String? {
        ptkKillUnavailableDiagnostic?.title
    }
}

extension String {
    var ptkDisplayProcessName: String {
        split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? self
    }
}

struct PortChangePresenter {
    func displayText(for change: PortChange) -> String {
        var parts = ["\(change.port)", label(for: change.kind)]
        if let processName = change.processName, !processName.isEmpty {
            parts.append(processName.ptkDisplayProcessName)
        }
        if let pid = change.pid {
            parts.append("PID \(pid)")
        }
        return parts.joined(separator: " · ")
    }

    private func label(for kind: PortChangeKind) -> String {
        switch kind {
        case .opened:
            "열림"
        case .closed:
            "닫힘"
        case .changed:
            "변경"
        }
    }
}
@MainActor
final class PortMonitorViewModel: ObservableObject {
    @Published var statuses: [PortStatus] = []
    @Published var serviceStatuses: [ServiceStatus] = []
    @Published var dockerContainerRows: [DockerContainerPortRow] = []
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

    var profileOptions: [PortProfileOption] {
        let presetOptions = portPresets.map {
            PortProfileOption(
                id: "preset-\($0.id)",
                title: $0.title,
                expression: $0.expression
            )
        }
        let customOptions = customPortProfiles.map {
            PortProfileOption(
                id: "custom-\($0.id)",
                title: $0.title,
                expression: $0.expression
            )
        }
        return presetOptions + customOptions
    }

    var currentProfileTitle: String {
        profileOptions.first { $0.expression == portExpression }?.title ?? "Custom"
    }

    var groupedServiceStatuses: [ServiceStatusGroup] {
        let builtInStatuses = serviceStatuses.filter { $0.group == .builtIn }
        let customStatuses = serviceStatuses.filter { $0.group == .custom }
        return [
            ServiceStatusGroup(id: .builtIn, title: ServiceGroup.builtIn.label, statuses: builtInStatuses),
            ServiceStatusGroup(id: .custom, title: ServiceGroup.custom.label, statuses: customStatuses)
        ].filter { !$0.statuses.isEmpty }
    }

    var customServiceEmptyMessage: String? {
        customServiceEndpoints.isEmpty
            ? "No custom services yet. Add read-only port checks in Settings."
            : nil
    }

    var showsServiceGroupHeaders: Bool {
        groupedServiceStatuses.count > 1 || customServiceEmptyMessage != nil
    }

    var serviceStatusSummary: String {
        let runningCount = serviceStatuses.filter { $0.state == .running }.count
        return "\(runningCount)/\(serviceStatuses.count)"
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

    func applyProfileOption(_ option: PortProfileOption) throws {
        try saveExpression(option.expression)
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

    func copyDockerContainerURL(for row: DockerContainerPortRow) {
        guard !row.isSummary, row.copyCandidates.count == 1, let candidate = row.copyCandidates.first else { return }
        onCopyText(candidate.urlString)
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
        if let diagnostic = status.ptkKillUnavailableDiagnostic {
            lines.append("Kill unavailable: \(diagnostic.title)")
            if let detail = diagnostic.detail {
                lines.append("Detail: \(detail)")
            }
            lines.append("Hint: \(diagnostic.hint)")
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
