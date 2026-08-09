import Testing
import Foundation
@testable import PTKCore

@Suite struct AppSettingsTests {
    @Test func usesDocumentedDefaultsWhenStoreIsEmpty() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.watchedPortsExpression == AppDefaults.defaultWatchedPortsExpression)
        #expect(settings.refreshInterval == .threeSeconds)
        #expect(settings.theme == .system)
        #expect(!settings.isAIUsageEnabled)
    }

    @Test func persistsWatchedPortsRefreshIntervalAndTheme() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        settings.watchedPortsExpression = "3000,5173"
        settings.refreshInterval = .tenSeconds
        settings.theme = .dark
        settings.isAIUsageEnabled = true

        let reloaded = AppSettings(store: store)
        #expect(reloaded.watchedPortsExpression == "3000,5173")
        #expect(reloaded.refreshInterval == .tenSeconds)
        #expect(reloaded.theme == .dark)
        #expect(reloaded.isAIUsageEnabled)
    }

    @Test func validatedWatchedPortsUpdateRejectsInvalidExpressionWithoutPersisting() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        try settings.updateWatchedPortsExpression("3000", parser: PortRangeParser())

        #expect(throws: PortRangeParserError.invalidToken("nope")) {
            try settings.updateWatchedPortsExpression("nope", parser: PortRangeParser())
        }
        #expect(settings.watchedPortsExpression == "3000")
    }

    @Test func customPortProfilesPersistReplaceAndDeleteByName() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        try settings.saveCustomPortProfile(title: " Work API ", expression: " 8000-8002 ")
        try settings.saveCustomPortProfile(title: "Frontend", expression: "3000,5173")
        try settings.saveCustomPortProfile(title: "work api", expression: "8080")

        let reloaded = AppSettings(store: store)
        #expect(reloaded.customPortProfiles.map(\.title) == ["Frontend", "work api"])
        #expect(reloaded.customPortProfiles.map(\.expression) == ["3000,5173", "8080"])

        try reloaded.deleteCustomPortProfile(id: "frontend")
        #expect(reloaded.customPortProfiles.map(\.id) == ["work api"])
    }

    @Test func customPortProfilesRejectEmptyNameAndInvalidExpression() throws {
        let settings = AppSettings(store: InMemorySettingsStore())

        #expect(throws: AppSettingsError.emptyProfileName) {
            try settings.saveCustomPortProfile(title: " ", expression: "3000")
        }
        #expect(throws: PortRangeParserError.invalidToken("nope")) {
            try settings.saveCustomPortProfile(title: "Broken", expression: "nope")
        }
        #expect(settings.customPortProfiles.isEmpty)
    }

    @Test func malformedProfileStorageIsReportedAndPreservedOnSaveAndDelete() {
        let store = InMemorySettingsStore()
        let original = #"not json"#
        store.set(original, forKey: AppSettings.Key.customPortProfiles)
        let settings = AppSettings(store: store)

        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.customPortProfiles)) {
            try settings.loadCustomPortProfiles()
        }
        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.customPortProfiles)) {
            try settings.saveCustomPortProfile(title: "New", expression: "3000")
        }
        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.customPortProfiles)) {
            try settings.deleteCustomPortProfile(id: "old")
        }
        #expect(store.string(forKey: AppSettings.Key.customPortProfiles) == original)
    }

    @Test func partiallyMalformedServiceStorageIsReportedAndPreserved() {
        let store = InMemorySettingsStore()
        let original = #"[{"name":"PostgreSQL","port":5432},{"name":"Broken"}]"#
        store.set(original, forKey: AppSettings.Key.customServiceEndpoints)
        let settings = AppSettings(store: store)

        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.customServiceEndpoints)) {
            try settings.loadCustomServiceEndpoints()
        }
        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.customServiceEndpoints)) {
            try settings.saveCustomServiceEndpoint(name: "Cache", port: 16379)
        }
        #expect(store.string(forKey: AppSettings.Key.customServiceEndpoints) == original)
    }

    @Test func customServicesRejectBuiltInDatabasePorts() throws {
        let settings = AppSettings(store: InMemorySettingsStore())

        for endpoint in ServiceMonitor.defaultDatabaseEndpoints {
            #expect(throws: AppSettingsError.builtInServicePort(endpoint.port)) {
                try settings.saveCustomServiceEndpoint(name: "Custom \(endpoint.name)", port: Int(endpoint.port))
            }
        }
        #expect(settings.customServiceEndpoints.isEmpty)

        #expect(throws: AppSettingsError.builtInServicePort(5432)) {
            try settings.replaceSettings(
                watchedPortsExpression: "3000",
                refreshInterval: .threeSeconds,
                theme: .system,
                profiles: [],
                serviceEndpoints: [DatabaseEndpoint(name: "Local PostgreSQL", port: 5432)],
                portChangeNotificationPreference: .init(isEnabled: false, portsExpression: nil)
            )
        }
        #expect(settings.customServiceEndpoints.isEmpty)

        try settings.saveCustomServiceEndpoint(name: "Custom API", port: 15432)
        #expect(settings.customServiceEndpoints.map(\.port) == [15432])
    }

    @Test func unchangedLegacyBuiltInServiceDoesNotBlockUnrelatedSettingsSave() throws {
        let store = InMemorySettingsStore()
        let legacyEndpoint = DatabaseEndpoint(name: "Legacy Redis", port: 6379)
        let storedEndpoints = String(
            data: try JSONEncoder().encode([legacyEndpoint]),
            encoding: .utf8
        )!
        store.set(storedEndpoints, forKey: AppSettings.Key.customServiceEndpoints)
        let settings = AppSettings(store: store)

        try settings.replaceSettings(
            watchedPortsExpression: "3000",
            refreshInterval: .fiveSeconds,
            theme: .dark,
            profiles: [],
            serviceEndpoints: [legacyEndpoint],
            portChangeNotificationPreference: .init(isEnabled: false, portsExpression: nil),
            isAIUsageEnabled: true
        )

        #expect(settings.customServiceEndpoints == [legacyEndpoint])
        #expect(settings.theme == .dark)
        #expect(settings.isAIUsageEnabled)
        #expect(throws: AppSettingsError.builtInServicePort(6379)) {
            try settings.replaceSettings(
                watchedPortsExpression: "3000",
                refreshInterval: .fiveSeconds,
                theme: .dark,
                profiles: [],
                serviceEndpoints: [DatabaseEndpoint(name: "Renamed Redis", port: 6379)],
                portChangeNotificationPreference: .init(isEnabled: false, portsExpression: nil),
                isAIUsageEnabled: true
            )
        }
    }

    @Test func corruptNotificationValuesArePreserved() throws {
        let store = RecordingSettingsStore()
        store.set(1.0, forKey: AppSettings.Key.portChangeNotificationsEnabled)
        store.mutations.removeAll()
        let settings = AppSettings(store: store)

        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.portChangeNotificationsEnabled)) {
            try settings.replaceSettings(
                watchedPortsExpression: "3000",
                refreshInterval: .threeSeconds,
                theme: .system,
                profiles: [],
                serviceEndpoints: [],
                portChangeNotificationPreference: PortChangeNotificationPreference(
                    isEnabled: false,
                    portsExpression: nil
                )
            )
        }
        #expect(store.double(forKey: AppSettings.Key.portChangeNotificationsEnabled) == 1.0)
        #expect(store.mutations.isEmpty)
    }

    @Test func notificationWritesRemainFailClosedInOrder() throws {
        let store = RecordingSettingsStore()
        let settings = AppSettings(store: store)

        try replaceSettings(
            settings,
            watched: "3000",
            preference: PortChangeNotificationPreference(isEnabled: true, portsExpression: "3000")
        )
        let notificationMutations = store.mutations.filter {
            $0 == AppSettings.Key.portChangeNotificationPortsExpression ||
                $0 == AppSettings.Key.portChangeNotificationsEnabled
        }
        #expect(notificationMutations == [
            AppSettings.Key.portChangeNotificationPortsExpression,
            AppSettings.Key.portChangeNotificationsEnabled,
        ])

        store.mutations.removeAll()
        try replaceSettings(
            settings,
            watched: "3000",
            preference: PortChangeNotificationPreference(isEnabled: false, portsExpression: "3000")
        )
        #expect(store.mutations.first == AppSettings.Key.portChangeNotificationsEnabled)
    }

    private func replaceSettings(
        _ settings: AppSettings,
        watched: String,
        preference: PortChangeNotificationPreference
    ) throws {
        try settings.replaceSettings(
            watchedPortsExpression: watched,
            refreshInterval: .threeSeconds,
            theme: .system,
            profiles: [],
            serviceEndpoints: [],
            portChangeNotificationPreference: preference
        )
    }
}

private final class RecordingSettingsStore: SettingsStore {
    private let storage = InMemorySettingsStore()
    var mutations: [String] = []

    func containsValue(forKey key: String) -> Bool {
        storage.containsValue(forKey: key)
    }

    func string(forKey key: String) -> String? {
        storage.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        mutations.append(key)
        storage.set(value, forKey: key)
    }

    func double(forKey key: String) -> Double? {
        storage.double(forKey: key)
    }

    func set(_ value: Double, forKey key: String) {
        mutations.append(key)
        storage.set(value, forKey: key)
    }

    func bool(forKey key: String) -> Bool? {
        storage.bool(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        mutations.append(key)
        storage.set(value, forKey: key)
    }
}
