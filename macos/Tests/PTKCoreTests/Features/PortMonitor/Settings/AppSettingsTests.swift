import Testing
@testable import PTKCore

@Suite struct AppSettingsTests {
    @Test func usesDocumentedDefaultsWhenStoreIsEmpty() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.watchedPortsExpression == AppDefaults.defaultWatchedPortsExpression)
        #expect(settings.refreshInterval == .threeSeconds)
    }

    @Test func persistsWatchedPortsAndRefreshInterval() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)

        settings.watchedPortsExpression = "3000,5173"
        settings.refreshInterval = .tenSeconds

        let reloaded = AppSettings(store: store)
        #expect(reloaded.watchedPortsExpression == "3000,5173")
        #expect(reloaded.refreshInterval == .tenSeconds)
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
}
