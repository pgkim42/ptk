import Testing
import Foundation
@testable import PTKCore

@Suite struct AppSettingsTests {
    @Test func usesDocumentedDefaultsWhenStoreIsEmpty() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.watchedPortsExpression == AppDefaults.defaultWatchedPortsExpression)
        #expect(settings.refreshInterval == .threeSeconds)
        #expect(settings.theme == .system)
    }

    @Test func persistsWatchedPortsRefreshIntervalAndTheme() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        settings.watchedPortsExpression = "3000,5173"
        settings.refreshInterval = .tenSeconds
        settings.theme = .dark

        let reloaded = AppSettings(store: store)
        #expect(reloaded.watchedPortsExpression == "3000,5173")
        #expect(reloaded.refreshInterval == .tenSeconds)
        #expect(reloaded.theme == .dark)
    }

    @Test func fallsBackToSystemThemeWhenStoredThemeIsUnknown() {
        let store = InMemorySettingsStore()
        store.set("solarized", forKey: AppSettings.Key.theme)

        let reloaded = AppSettings(store: store)

        #expect(reloaded.theme == .system)
    }

    @Test func themeLabelsStayStableForSettingsPicker() {
        #expect(AppTheme.allCases.map(\.label) == ["시스템", "라이트", "다크"])
    }

    @Test func portPresetsExposeValidatedProfiles() throws {
        let parser = PortRangeParser()

        #expect(AppDefaults.portPresets.map(\.id) == ["full-stack", "frontend", "api", "data"])
        #expect(AppDefaults.portPresets.map(\.title) == ["Full Stack", "Frontend", "API", "Data"])
        #expect(AppDefaults.portPresets.first?.expression == AppDefaults.defaultWatchedPortsExpression)

        for preset in AppDefaults.portPresets {
            let ports = try parser.parse(preset.expression)
            #expect(!ports.isEmpty)
        }
    }

    @Test func validatedWatchedPortsUpdatePersistsValidExpression() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        try settings.updateWatchedPortsExpression("3000,5173-5174", parser: PortRangeParser())

        let reloaded = AppSettings(store: store)
        #expect(reloaded.watchedPortsExpression == "3000,5173-5174")
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

    @Test func customServiceEndpointsPersistReplaceAndDeleteByNameAndPort() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        try settings.saveCustomServiceEndpoint(name: " RabbitMQ ", port: 5672)
        try settings.saveCustomServiceEndpoint(name: "LocalStack", port: 4566)
        try settings.saveCustomServiceEndpoint(name: "rabbitmq", port: 5672)

        let reloaded = AppSettings(store: store)
        #expect(reloaded.customServiceEndpoints.map(\.name) == ["LocalStack", "rabbitmq"])
        #expect(reloaded.customServiceEndpoints.map(\.port) == [4566, 5672])

        try reloaded.deleteCustomServiceEndpoint(id: "localstack-4566")
        #expect(reloaded.customServiceEndpoints.map(\.id) == ["rabbitmq-5672"])
    }

    @Test func customServiceEndpointsRejectEmptyNameAndInvalidPort() throws {
        let settings = AppSettings(store: InMemorySettingsStore())

        #expect(throws: AppSettingsError.emptyServiceName) {
            try settings.saveCustomServiceEndpoint(name: " ", port: 5672)
        }
        #expect(throws: AppSettingsError.invalidServicePort) {
            try settings.saveCustomServiceEndpoint(name: "Broken", port: 0)
        }
        #expect(throws: AppSettingsError.invalidServicePort) {
            try settings.saveCustomServiceEndpoint(name: "Broken", port: 70_000)
        }
        #expect(settings.customServiceEndpoints.isEmpty)
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

    @Test func missingCustomCollectionsLoadAsEmpty() throws {
        let settings = AppSettings(store: InMemorySettingsStore())

        #expect(try settings.loadCustomPortProfiles().isEmpty)
        #expect(try settings.loadCustomServiceEndpoints().isEmpty)
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
            try settings.saveCustomServiceEndpoint(name: "Redis", port: 6379)
        }
        #expect(store.string(forKey: AppSettings.Key.customServiceEndpoints) == original)
    }

    @Test func storedValueWithWrongTypeIsCorruptRatherThanMissing() {
        let store = InMemorySettingsStore()
        store.set(1.0, forKey: AppSettings.Key.customPortProfiles)
        let settings = AppSettings(store: store)

        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.customPortProfiles)) {
            try settings.loadCustomPortProfiles()
        }
    }
    @Test func notificationPreferenceDefaultsToOffWithoutWriting() throws {
        let store = RecordingSettingsStore()
        let settings = AppSettings(store: store)

        #expect(try settings.loadPortChangeNotificationPreference() ==
            PortChangeNotificationPreference(isEnabled: false, portsExpression: nil))
        #expect(store.mutations.isEmpty)
    }

    @Test func notificationPreferenceRoundTripsStrictBooleans() throws {
        let store = InMemorySettingsStore()
        store.set(true, forKey: AppSettings.Key.portChangeNotificationsEnabled)
        store.set("3000,5173", forKey: AppSettings.Key.portChangeNotificationPortsExpression)

        #expect(try AppSettings(store: store).loadPortChangeNotificationPreference() ==
            PortChangeNotificationPreference(isEnabled: true, portsExpression: "3000,5173"))

        store.set(false, forKey: AppSettings.Key.portChangeNotificationsEnabled)
        #expect(try AppSettings(store: store).loadPortChangeNotificationPreference().isEnabled == false)
    }

    @Test func userDefaultsBooleanReaderRejectsNonBooleanValues() throws {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let key = AppSettings.Key.portChangeNotificationsEnabled

        #expect(store.bool(forKey: key) == nil)
        defaults.set(false, forKey: key)
        #expect(store.bool(forKey: key) == false)
        defaults.set(true, forKey: key)
        #expect(store.bool(forKey: key) == true)

        for value: Any in [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: 2.5), "true"] {
            defaults.set(value, forKey: key)
            #expect(store.bool(forKey: key) == nil)
            #expect(throws: AppSettingsError.corruptStoredValue(key)) {
                try AppSettings(store: store).loadPortChangeNotificationPreference()
            }
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
    @Test func wrongTypedNotificationExpressionIsCorruptAndPreserved() {
        let store = RecordingSettingsStore()
        store.set(1.0, forKey: AppSettings.Key.portChangeNotificationPortsExpression)
        store.mutations.removeAll()
        let settings = AppSettings(store: store)

        #expect(throws: AppSettingsError.corruptStoredValue(AppSettings.Key.portChangeNotificationPortsExpression)) {
            try replaceSettings(
                settings,
                watched: "3000",
                preference: PortChangeNotificationPreference(isEnabled: false, portsExpression: nil)
            )
        }
        #expect(store.double(forKey: AppSettings.Key.portChangeNotificationPortsExpression) == 1.0)
        #expect(store.mutations.isEmpty)
    }

    @Test func firstEnableCopiesWatchedExpressionAndLaterTogglesPreserveIt() throws {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        try replaceSettings(
            settings,
            watched: " 3000, 5173 ",
            preference: PortChangeNotificationPreference(isEnabled: true, portsExpression: nil)
        )
        #expect(try settings.loadPortChangeNotificationPreference() ==
            PortChangeNotificationPreference(isEnabled: true, portsExpression: "3000, 5173"))
        #expect(settings.portChangeNotificationEligibilityRevision == 1)

        try replaceSettings(
            settings,
            watched: "8080",
            preference: PortChangeNotificationPreference(isEnabled: false, portsExpression: "3000, 5173")
        )
        #expect(settings.portChangeNotificationEligibilityRevision == 2)
        try replaceSettings(
            settings,
            watched: "9000",
            preference: PortChangeNotificationPreference(isEnabled: true, portsExpression: nil)
        )
        #expect(try settings.loadPortChangeNotificationPreference() ==
            PortChangeNotificationPreference(isEnabled: true, portsExpression: "3000, 5173"))
        #expect(settings.portChangeNotificationEligibilityRevision == 3)

        try replaceSettings(
            settings,
            watched: "9000",
            preference: PortChangeNotificationPreference(isEnabled: true, portsExpression: "3000, 5173")
        )
        #expect(settings.portChangeNotificationEligibilityRevision == 3)
    }

    @Test func disabledInvalidNotificationExpressionDoesNotBlockOtherSettingsChanges() throws {
        let store = InMemorySettingsStore()
        store.set(false, forKey: AppSettings.Key.portChangeNotificationsEnabled)
        store.set("not-a-port", forKey: AppSettings.Key.portChangeNotificationPortsExpression)
        let settings = AppSettings(store: store)

        try replaceSettings(
            settings,
            watched: "8080",
            preference: PortChangeNotificationPreference(isEnabled: false, portsExpression: "not-a-port")
        )

        #expect(settings.watchedPortsExpression == "8080")
        #expect(try settings.loadPortChangeNotificationPreference() ==
            PortChangeNotificationPreference(isEnabled: false, portsExpression: "not-a-port"))
        #expect(settings.portChangeNotificationEligibilityRevision == 0)
    }
    @Test func notificationPreferenceRejectsInvalidAndOverLimitExpressionsBeforeWriting() {
        let store = RecordingSettingsStore()
        let settings = AppSettings(store: store)

        #expect(throws: PortRangeParserError.invalidToken("nope")) {
            try replaceSettings(
                settings,
                watched: "3000",
                preference: PortChangeNotificationPreference(isEnabled: true, portsExpression: "nope")
            )
        }
        #expect(store.mutations.isEmpty)

        #expect(throws: PortRangeParserError.maxPortCountExceeded(AppDefaults.maxPortCount)) {
            try replaceSettings(
                settings,
                watched: "3000",
                preference: PortChangeNotificationPreference(isEnabled: true, portsExpression: "1-5001")
            )
        }
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
