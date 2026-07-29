import Foundation
import Testing
@testable import PTKCore

@Suite("AI usage monitor")
struct AIUsageMonitorTests {
    @Test func refreshIntervalProtectsProviderRateLimits() {
        #expect(AIUsageMonitor.refreshInterval == 10 * 60)
    }
    @Test func parsesClaudeSessionAndWeeklyLimits() throws {
        let data = Data(#"{"limits":[{"kind":"session","percent":24,"resets_at":"2026-07-29T12:00:00Z"},{"kind":"weekly_all","percent":61}]}"#.utf8)

        let windows = try AIUsageResponseParser().parseClaude(data)

        #expect(windows.map(\.label) == ["5시간", "주간"])
        #expect(windows.map(\.usedPercentage) == [24, 61])
        #expect(windows[0].resetsAt != nil)
        #expect(windows.map(\.remainingPercentage) == [76, 39])
    }

    @Test func parsesCodexWindowsAndConvertsRemainingPercentage() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":72,"reset_at":1785326400},"secondary_window":{"remaining_percentage":59}}}"#.utf8)

        let windows = try AIUsageResponseParser().parseCodex(data)

        #expect(windows.map(\.label) == ["5시간", "주간"])
        #expect(windows.map(\.usedPercentage) == [72, 41])
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1_785_326_400))
        #expect(windows.map(\.remainingPercentage) == [28, 59])
    }

    @Test func clampsUnexpectedPercentagesAndIgnoresUnknownBodies() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":140},"secondary_window":{}}}"#.utf8)

        let windows = try AIUsageResponseParser().parseCodex(data)

        #expect(windows == [AIUsageWindow(label: "5시간", usedPercentage: 100, resetsAt: nil)])
        #expect(try AIUsageResponseParser().parseClaude(Data("{}".utf8)).isEmpty)
    }
}
