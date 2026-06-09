public struct PortMenuRow: Equatable, Sendable {
    public let port: UInt16
    public let pid: Int?
    public let processName: String?
    public let displayText: String
    public let canRequestKill: Bool
    public let killUnavailableCause: KillUnavailableCause?
    public let killTarget: KillTarget?

    public init(status: PortStatus) {
        self.port = status.port
        self.pid = status.pid
        self.processName = status.processName

        var parts = ["Port \(status.port)"]
        if let pid = status.pid {
            parts.append("PID \(pid)")
        }
        if let processName = status.processName, !processName.isEmpty {
            parts.append(processName)
        }
        self.displayText = parts.joined(separator: " · ")
        self.killUnavailableCause = status.killUnavailableCause
        self.killTarget = KillTarget.safe(port: status.port, pid: status.pid, processName: status.processName)
        self.canRequestKill = killTarget != nil
    }
}

public struct MenuModel: Equatable, Sendable {
    public let title: String
    public let rows: [PortMenuRow]
    public let refreshIntervals: [RefreshInterval]
    public let selectedRefreshInterval: RefreshInterval
    public let errorMessage: String?

    public init(
        statuses: [PortStatus],
        selectedRefreshInterval: RefreshInterval = AppDefaults.defaultRefreshInterval,
        errorMessage: String? = nil
    ) {
        let openStatuses = statuses.filter(\.isOpen).sorted { $0.port < $1.port }
        self.title = "\(AppDefaults.appName) \(openStatuses.count)"
        self.rows = openStatuses.map(PortMenuRow.init(status:))
        self.refreshIntervals = RefreshInterval.allCases
        self.selectedRefreshInterval = selectedRefreshInterval
        self.errorMessage = errorMessage
    }

    public var isEmpty: Bool { rows.isEmpty }
}
