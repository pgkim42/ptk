import Foundation

public enum AppTheme: String, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: "시스템"
        case .light: "라이트"
        case .dark: "다크"
        }
    }
}

public protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func double(forKey key: String) -> Double?
    func set(_ value: Double, forKey key: String)
}

public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func double(forKey key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    public func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        values[key] as? String
    }

    public func set(_ value: String, forKey key: String) {
        values[key] = value
    }

    public func double(forKey key: String) -> Double? {
        values[key] as? Double
    }

    public func set(_ value: Double, forKey key: String) {
        values[key] = value
    }
}

public final class AppSettings {
    public enum Key {
        public static let watchedPortsExpression = "watchedPortsExpression"
        public static let refreshInterval = "refreshIntervalSeconds"
        public static let theme = "theme"
    }

    private let store: SettingsStore

    public init(store: SettingsStore = UserDefaultsSettingsStore()) {
        self.store = store
    }

    public var watchedPortsExpression: String {
        get { store.string(forKey: Key.watchedPortsExpression) ?? AppDefaults.defaultWatchedPortsExpression }
        set { store.set(newValue, forKey: Key.watchedPortsExpression) }
    }

    public func updateWatchedPortsExpression(
        _ expression: String,
        parser: PortRangeParser = PortRangeParser()
    ) throws {
        _ = try parser.parse(expression)
        watchedPortsExpression = expression
    }

    public var refreshInterval: RefreshInterval {
        get {
            guard let seconds = store.double(forKey: Key.refreshInterval),
                  let interval = RefreshInterval(rawValue: seconds) else {
                return AppDefaults.defaultRefreshInterval
            }
            return interval
        }
        set { store.set(newValue.rawValue, forKey: Key.refreshInterval) }
    }

    public var theme: AppTheme {
        get {
            guard let rawValue = store.string(forKey: Key.theme),
                  let theme = AppTheme(rawValue: rawValue) else {
                return .system
            }
            return theme
        }
        set { store.set(newValue.rawValue, forKey: Key.theme) }
    }
}
