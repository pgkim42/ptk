import Foundation
import Testing
@testable import PTKCore

@Suite("AI usage monitor")
struct AIUsageMonitorTests {
    @Test func refreshIntervalProtectsProviderRateLimits() {
        #expect(AIUsageMonitor.refreshInterval == 10 * 60)
    }

    @Test func liveRequestsUseAnEphemeralNonCachingSession() {
        let session = AIUsageMonitor.ephemeralSession()
        defer { session.invalidateAndCancel() }

        #expect(session.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(session.configuration.urlCache == nil)
        #expect(session.configuration.httpCookieStorage == nil)
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

    @Test func parsesCodexWindowDurationsWhenLegacyPayloadProvidesThem() throws {
        let camelAndSeconds = Data(#"{"rate_limit":{"primary_window":{"used_percent":10,"windowDurationMins":90},"secondary_window":{"used_percent":20,"limit_window_seconds":172800}}}"#.utf8)
        let snakeMinutes = Data(#"{"rate_limit":{"primary_window":{"used_percent":30,"window_duration_mins":120}}}"#.utf8)

        let firstWindows = try AIUsageResponseParser().parseCodex(camelAndSeconds)
        let secondWindows = try AIUsageResponseParser().parseCodex(snakeMinutes)

        #expect(firstWindows.map(\.label) == ["90분", "2일"])
        #expect(secondWindows.map(\.label) == ["2시간"])
    }

    @Test func parsesFractionalISO8601ResetDate() throws {
        let data = Data(#"{"limits":[{"kind":"session","percent":24,"resets_at":"2026-07-29T12:00:00.123Z"}]}"#.utf8)

        let windows = try AIUsageResponseParser().parseClaude(data)

        #expect(abs((windows[0].resetsAt?.timeIntervalSince1970 ?? 0) - 1_785_326_400.123) < 0.001)
    }

    @Test func invalidProviderResponseIsNotReportedAsMissingCredentials() {
        #expect(throws: AIUsageMonitorError.invalidResponse) {
            try AIUsageResponseParser().parseClaude(Data("{".utf8))
        }
        #expect(AIUsageMonitor.errorMessage(for: AIUsageMonitorError.invalidResponse) == "응답 해석 실패")
        #expect(AIUsageMonitor.errorMessage(for: AIUsageMonitorError.credentialsUnavailable) == "로그인 정보 없음")
    }

    @Test func codexFileAuthenticationHonorsCodexHomeAndNamesItsLimitation() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        #expect(AIUsageMonitor.codexAuthURL(
            environment: ["CODEX_HOME": "/tmp/custom-codex"],
            homeDirectory: homeDirectory
        ).path == "/tmp/custom-codex/auth.json")
        #expect(AIUsageMonitor.codexAuthURL(
            environment: [:],
            homeDirectory: homeDirectory
        ).path == "/Users/example/.codex/auth.json")
        #expect(AIUsageMonitor.errorMessage(for: AIUsageMonitorError.codexFileCredentialsUnavailable) == "지원되는 Codex 파일 인증 없음")
    }

    @Test func clampsUnexpectedPercentagesAndIgnoresUnknownBodies() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":140},"secondary_window":{}}}"#.utf8)

        let windows = try AIUsageResponseParser().parseCodex(data)

        #expect(windows == [AIUsageWindow(label: "5시간", usedPercentage: 100, resetsAt: nil)])
        #expect(try AIUsageResponseParser().parseClaude(Data("{}".utf8)).isEmpty)
    }
}
