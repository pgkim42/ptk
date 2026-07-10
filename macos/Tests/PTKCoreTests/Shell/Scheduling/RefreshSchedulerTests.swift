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

    @Test func delayedCompletionKeepsRequestInFlightAndBlocksOverlap() {
        var completion: (@MainActor () -> Void)?
        let scheduler = RefreshScheduler { _, finish in
            completion = finish
        }

        #expect(scheduler.triggerManualRefresh() == .started)
        #expect(scheduler.isInFlight)
        #expect(scheduler.triggerTimerRefresh() == .skippedInFlight)
        #expect(scheduler.isInFlight)

        completion?()
        #expect(!scheduler.isInFlight)
        #expect(scheduler.triggerTimerRefresh() == .started)
        #expect(scheduler.isInFlight)
        completion?()
        #expect(!scheduler.isInFlight)
    }

    @Test func duplicateCompletionCannotFinishLaterRequest() {
        var callbackCount = 0
        var firstCompletion: (@MainActor () -> Void)?
        var secondCompletion: (@MainActor () -> Void)?
        let scheduler = RefreshScheduler { _, completion in
            callbackCount += 1
            if callbackCount == 1 {
                firstCompletion = completion
            } else {
                secondCompletion = completion
            }
        }

        #expect(scheduler.triggerManualRefresh() == .started)
        firstCompletion?()
        #expect(!scheduler.isInFlight)

        #expect(scheduler.triggerSettingsRefresh() == .started)
        #expect(scheduler.isInFlight)
        firstCompletion?()
        #expect(scheduler.isInFlight)

        secondCompletion?()
        #expect(!scheduler.isInFlight)
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
