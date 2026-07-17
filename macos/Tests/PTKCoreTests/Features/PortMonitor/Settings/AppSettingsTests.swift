import Testing
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
}
