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

public enum RefreshTrigger: Equatable, Sendable {
    case startup
    case timer
    case manual
    case settings
    case kill
}

public enum RefreshTriggerResult: Equatable, Sendable {
    case started
    case skippedInFlight
    case stopped
}

@MainActor
public final class RefreshScheduler {
    private final class RequestToken {}

    public private(set) var interval: RefreshInterval
    public private(set) var scheduleGeneration: Int = 0
    public var isInFlight: Bool {
        activeToken != nil
    }

    private var activeToken: RequestToken?
    private var isStopped = false
    private let refresh: (RefreshTrigger, @escaping @MainActor () -> Void) -> Void

    public init(
        interval: RefreshInterval = .defaultValue,
        refresh: @escaping (RefreshTrigger, @escaping @MainActor () -> Void) -> Void
    ) {
        self.interval = interval
        self.refresh = refresh
    }

    public func changeInterval(to interval: RefreshInterval) {
        guard self.interval != interval else { return }
        self.interval = interval
        scheduleGeneration += 1
    }

    @discardableResult
    public func triggerStartupRefresh() -> RefreshTriggerResult {
        trigger(.startup)
    }

    @discardableResult
    public func triggerTimerRefresh() -> RefreshTriggerResult {
        trigger(.timer)
    }

    @discardableResult
    public func triggerManualRefresh() -> RefreshTriggerResult {
        trigger(.manual)
    }

    @discardableResult
    public func triggerSettingsRefresh() -> RefreshTriggerResult {
        trigger(.settings)
    }

    @discardableResult
    public func triggerKillRefresh() -> RefreshTriggerResult {
        trigger(.kill)
    }

    public func stop() {
        isStopped = true
        activeToken = nil
    }

    private func trigger(_ trigger: RefreshTrigger) -> RefreshTriggerResult {
        guard !isStopped else { return .stopped }
        guard activeToken == nil else { return .skippedInFlight }

        let token = RequestToken()
        activeToken = token
        refresh(trigger) { [weak self] in
            self?.finishRefresh(token)
        }
        return .started
    }

    private func finishRefresh(_ token: RequestToken) {
        guard activeToken === token else { return }
        activeToken = nil
    }
}
