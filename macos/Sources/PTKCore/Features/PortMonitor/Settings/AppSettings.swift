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

public struct PortProfile: Equatable, Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let expression: String

    public init(id: String, title: String, expression: String) {
        self.id = id
        self.title = title
        self.expression = expression
    }
}

public enum AppSettingsError: Error, Equatable, CustomStringConvertible {
    case emptyProfileName
    case emptyServiceName
    case invalidServicePort
    case corruptStoredValue(String)

    public var description: String {
        switch self {
        case .emptyProfileName:
            return "profile name is empty"
        case .emptyServiceName:
            return "service name is empty"
        case .invalidServicePort:
            return "service port must be between 1 and 65535"
        case .corruptStoredValue(let key):
            return "stored settings could not be read: \(key)"
        }
    }
}

public protocol SettingsStore: AnyObject {
    func containsValue(forKey key: String) -> Bool
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

    public func containsValue(forKey key: String) -> Bool {
        defaults.object(forKey: key) != nil
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
    public func containsValue(forKey key: String) -> Bool {
        values[key] != nil
    }


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
        public static let customPortProfiles = "customPortProfiles"
        public static let customServiceEndpoints = "customServiceEndpoints"
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

    public var customPortProfiles: [PortProfile] {
        (try? loadCustomPortProfiles()) ?? []
    }

    public var customServiceEndpoints: [DatabaseEndpoint] {
        (try? loadCustomServiceEndpoints()) ?? []
    }

    public func loadCustomPortProfiles() throws -> [PortProfile] {
        try loadCollection(forKey: Key.customPortProfiles)
    }

    public func loadCustomServiceEndpoints() throws -> [DatabaseEndpoint] {
        try loadCollection(forKey: Key.customServiceEndpoints)
    }

    public func saveCustomServiceEndpoint(name: String, port: Int) throws {
        let endpoint = try validatedServiceEndpoint(name: name, port: port)
        let current = try loadCustomServiceEndpoints()
        let updated = ([endpoint] + current.filter { $0.id != endpoint.id })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try persistCollection(updated, forKey: Key.customServiceEndpoints)
    }

    public func deleteCustomServiceEndpoint(id: String) throws {
        let current = try loadCustomServiceEndpoints()
        try persistCollection(current.filter { $0.id != id }, forKey: Key.customServiceEndpoints)
    }

    public func saveCustomPortProfile(
        title: String,
        expression: String,
        parser: PortRangeParser = PortRangeParser()
    ) throws {
        let profile = try validatedPortProfile(title: title, expression: expression, parser: parser)
        let current = try loadCustomPortProfiles()
        let updated = ([profile] + current.filter { $0.id != profile.id })
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        try persistCollection(updated, forKey: Key.customPortProfiles)
    }

    public func deleteCustomPortProfile(id: String) throws {
        let current = try loadCustomPortProfiles()
        try persistCollection(current.filter { $0.id != id }, forKey: Key.customPortProfiles)
    }

    public func replaceCustomCollections(
        profiles: [PortProfile],
        serviceEndpoints: [DatabaseEndpoint]
    ) throws {
        _ = try loadCustomPortProfiles()
        _ = try loadCustomServiceEndpoints()
        let encodedProfiles = try encodedCollection(profiles, forKey: Key.customPortProfiles)
        let encodedEndpoints = try encodedCollection(serviceEndpoints, forKey: Key.customServiceEndpoints)
        store.set(encodedProfiles, forKey: Key.customPortProfiles)
        store.set(encodedEndpoints, forKey: Key.customServiceEndpoints)
    }

    public func validatedPortProfile(
        title: String,
        expression: String,
        parser: PortRangeParser = PortRangeParser()
    ) throws -> PortProfile {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw AppSettingsError.emptyProfileName }
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try parser.parse(trimmedExpression)
        return PortProfile(
            id: trimmedTitle.lowercased(),
            title: trimmedTitle,
            expression: trimmedExpression
        )
    }

    public func validatedServiceEndpoint(name: String, port: Int) throws -> DatabaseEndpoint {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AppSettingsError.emptyServiceName }
        guard port > 0, port <= Int(UInt16.max) else { throw AppSettingsError.invalidServicePort }
        return DatabaseEndpoint(name: trimmedName, port: UInt16(port))
    }

    private func loadCollection<Value: Decodable>(forKey key: String) throws -> [Value] {
        guard store.containsValue(forKey: key) else { return [] }
        guard let rawValue = store.string(forKey: key),
              let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([Value].self, from: data) else {
            throw AppSettingsError.corruptStoredValue(key)
        }
        return values
    }

    private func persistCollection<Value: Encodable>(_ values: [Value], forKey key: String) throws {
        store.set(try encodedCollection(values, forKey: key), forKey: key)
    }

    private func encodedCollection<Value: Encodable>(_ values: [Value], forKey key: String) throws -> String {
        guard let rawValue = String(data: try JSONEncoder().encode(values), encoding: .utf8) else {
            throw AppSettingsError.corruptStoredValue(key)
        }
        return rawValue
    }
}
