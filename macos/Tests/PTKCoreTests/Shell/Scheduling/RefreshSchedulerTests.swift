import Testing
@testable import PTKCore

@Suite struct RefreshSchedulerTests {
    @Test func startsWithDefaultInterval() {
        let scheduler = RefreshScheduler(refresh: {})
        #expect(scheduler.interval == .threeSeconds)
    }

    @Test func changingIntervalSchedulesNewGeneration() {
        let scheduler = RefreshScheduler(refresh: {})
        scheduler.changeInterval(to: .fiveSeconds)
        #expect(scheduler.interval == .fiveSeconds)
        #expect(scheduler.scheduleGeneration == 1)

        scheduler.changeInterval(to: .fiveSeconds)
        #expect(scheduler.scheduleGeneration == 1)
    }

    @Test func manualRefreshRunsWhenIdle() {
        var calls = 0
        let scheduler = RefreshScheduler(refresh: { calls += 1 })
        #expect(scheduler.triggerManualRefresh() == .started)
        #expect(calls == 1)
    }

    @Test func overlappingRefreshIsSkipped() {
        let scheduler = RefreshScheduler(refresh: {})
        #expect(scheduler.beginRefreshForTesting() == .started)
        #expect(scheduler.triggerManualRefresh() == .skippedInFlight)
        scheduler.finishRefreshForTesting()
        #expect(scheduler.triggerManualRefresh() == .started)
    }
}
