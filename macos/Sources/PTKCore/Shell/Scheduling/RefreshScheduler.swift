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
    /// `true` while any accepted refresh receipt remains unsettled.
    ///
    /// Timer admission is keyed to the newest receipt, so a timer refresh may
    /// be accepted while this aggregate state remains `true`.
    public var isInFlight: Bool {
        !activeTokens.isEmpty
    }

    private var activeTokens: [ObjectIdentifier: RequestToken] = [:]
    private var newestToken: RequestToken?
    private var didTriggerStartup = false
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
        newestToken = nil
        activeTokens.removeAll()
    }

    private func trigger(_ trigger: RefreshTrigger) -> RefreshTriggerResult {
        guard !isStopped else { return .stopped }
        if trigger == .startup {
            guard !didTriggerStartup, activeTokens.isEmpty else { return .skippedInFlight }
            didTriggerStartup = true
        } else if trigger == .timer {
            guard newestToken == nil else { return .skippedInFlight }
        }

        let token = RequestToken()
        let tokenID = ObjectIdentifier(token)
        activeTokens[tokenID] = token
        newestToken = token
        refresh(trigger) { [weak self, token] in
            self?.finishRefresh(token)
        }
        return .started
    }

    private func finishRefresh(_ token: RequestToken) {
        let tokenID = ObjectIdentifier(token)
        guard activeTokens[tokenID] === token else { return }
        activeTokens.removeValue(forKey: tokenID)
        if newestToken === token {
            newestToken = nil
        }
    }
}
