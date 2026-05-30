public enum RefreshInterval: Double, CaseIterable, Equatable, Sendable {
    case oneSecond = 1
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    public static let defaultValue: RefreshInterval = .threeSeconds

    public var label: String {
        "\(Int(rawValue))s"
    }
}

public enum RefreshTriggerResult: Equatable, Sendable {
    case started
    case skippedInFlight
}

public final class RefreshScheduler {
    public private(set) var interval: RefreshInterval
    public private(set) var scheduleGeneration: Int = 0
    private var isInFlight = false
    private let refresh: () -> Void

    public init(interval: RefreshInterval = .defaultValue, refresh: @escaping () -> Void) {
        self.interval = interval
        self.refresh = refresh
    }

    public func changeInterval(to interval: RefreshInterval) {
        guard self.interval != interval else { return }
        self.interval = interval
        scheduleGeneration += 1
    }

    @discardableResult
    public func triggerManualRefresh() -> RefreshTriggerResult {
        guard !isInFlight else { return .skippedInFlight }
        isInFlight = true
        refresh()
        isInFlight = false
        return .started
    }

    @discardableResult
    public func beginRefreshForTesting() -> RefreshTriggerResult {
        guard !isInFlight else { return .skippedInFlight }
        isInFlight = true
        return .started
    }

    public func finishRefreshForTesting() {
        isInFlight = false
    }
}
