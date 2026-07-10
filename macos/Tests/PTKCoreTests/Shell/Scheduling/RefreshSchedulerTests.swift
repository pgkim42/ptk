import Testing
@testable import PTKCore

@MainActor
@Suite struct RefreshSchedulerTests {
    @Test func startsWithDefaultInterval() {
        let scheduler = RefreshScheduler { _, completion in
            completion()
        }

        #expect(scheduler.interval == .threeSeconds)
        #expect(scheduler.scheduleGeneration == 0)
        #expect(!scheduler.isInFlight)
    }

    @Test func changingIntervalSchedulesNewGeneration() {
        let scheduler = RefreshScheduler { _, completion in
            completion()
        }

        scheduler.changeInterval(to: .fiveSeconds)
        #expect(scheduler.interval == .fiveSeconds)
        #expect(scheduler.scheduleGeneration == 1)

        scheduler.changeInterval(to: .fiveSeconds)
        #expect(scheduler.scheduleGeneration == 1)

        scheduler.changeInterval(to: .oneSecond)
        #expect(scheduler.interval == .oneSecond)
        #expect(scheduler.scheduleGeneration == 2)
    }

    @Test func everyTriggerIsForwardedAndSynchronousCompletionFinishesRequest() {
        var receivedTriggers: [RefreshTrigger] = []
        let scheduler = RefreshScheduler { trigger, completion in
            receivedTriggers.append(trigger)
            completion()
        }

        #expect(scheduler.triggerStartupRefresh() == .started)
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerStartupRefresh() == .skippedInFlight)
        #expect(scheduler.triggerTimerRefresh() == .started)
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerManualRefresh() == .started)
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerSettingsRefresh() == .started)
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerKillRefresh() == .started)
        #expect(!scheduler.isInFlight)
        #expect(receivedTriggers == [.startup, .timer, .manual, .settings, .kill])
    }

    @Test func timerDuringOutstandingRefreshDoesNotReachController() {
        var receivedTriggers: [RefreshTrigger] = []
        var completion: (@MainActor () -> Void)?
        let scheduler = RefreshScheduler { trigger, finish in
            receivedTriggers.append(trigger)
            completion = finish
        }

        #expect(scheduler.triggerManualRefresh() == .started)
        #expect(scheduler.isInFlight)
        #expect(scheduler.triggerTimerRefresh() == .skippedInFlight)
        #expect(scheduler.triggerStartupRefresh() == .skippedInFlight)
        #expect(receivedTriggers == [.manual])

        completion?()
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerTimerRefresh() == .started)
        #expect(receivedTriggers == [.manual, .timer])
    }

    @Test func supersedingTriggersTrackIndependentCompletionReceipts() {
        var completions: [@MainActor () -> Void] = []
        var receivedTriggers: [RefreshTrigger] = []
        let scheduler = RefreshScheduler { trigger, completion in
            receivedTriggers.append(trigger)
            completions.append(completion)
        }

        #expect(scheduler.triggerManualRefresh() == .started)
        #expect(scheduler.triggerSettingsRefresh() == .started)
        #expect(scheduler.triggerKillRefresh() == .started)
        #expect(receivedTriggers == [.manual, .settings, .kill])
        #expect(scheduler.isInFlight)

        completions[1]()
        #expect(scheduler.isInFlight)
        completions[1]()
        #expect(scheduler.isInFlight)

        completions[0]()
        #expect(scheduler.isInFlight)
        completions[1]()
        #expect(scheduler.isInFlight)

        completions[2]()
        #expect(!scheduler.isInFlight)
    }

    @Test func timerUsesNewestReceiptButStartupRequiresTrueIdleAndIsAcceptedOnlyOnce() {
        var completions: [@MainActor () -> Void] = []
        var receivedTriggers: [RefreshTrigger] = []
        let scheduler = RefreshScheduler { trigger, completion in
            receivedTriggers.append(trigger)
            completions.append(completion)
        }

        #expect(scheduler.triggerManualRefresh() == .started)
        #expect(scheduler.triggerSettingsRefresh() == .started)
        #expect(scheduler.isInFlight)
        #expect(scheduler.triggerTimerRefresh() == .skippedInFlight)

        completions[1]()
        #expect(scheduler.isInFlight)
        #expect(scheduler.triggerStartupRefresh() == .skippedInFlight)
        #expect(scheduler.triggerTimerRefresh() == .started)
        #expect(receivedTriggers == [.manual, .settings, .timer])
        #expect(scheduler.isInFlight)

        completions[1]()
        completions[2]()
        #expect(scheduler.isInFlight)
        completions[0]()
        #expect(!scheduler.isInFlight)

        #expect(scheduler.triggerStartupRefresh() == .started)
        #expect(receivedTriggers == [.manual, .settings, .timer, .startup])
        completions[3]()
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerStartupRefresh() == .skippedInFlight)
    }

    @Test func stopInvalidatesActiveRequestAndLateCompletionDoesNothing() {
        var completion: (@MainActor () -> Void)?
        let scheduler = RefreshScheduler { _, finish in
            completion = finish
        }

        #expect(scheduler.triggerKillRefresh() == .started)
        #expect(scheduler.isInFlight)
        #expect(completion != nil)

        scheduler.stop()
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerStartupRefresh() == .stopped)

        completion?()
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerManualRefresh() == .stopped)
    }
}
