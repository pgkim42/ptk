import Foundation
import Security

public struct AIUsageWindow: Equatable, Sendable {
    public let label: String
    public let usedPercentage: Double?
    public let resetsAt: Date?
    public init(label: String, usedPercentage: Double?, resetsAt: Date?) { self.label = label; self.usedPercentage = usedPercentage; self.resetsAt = resetsAt }
    public var remainingPercentage: Double? { usedPercentage.map { 100 - $0 } }
}

public struct AIUsageProviderStatus: Equatable, Sendable {
    public enum Provider: String, Sendable { case claude = "Claude"; case codex = "Codex" }
    public let provider: Provider
    public let windows: [AIUsageWindow]
    public let errorMessage: String?
    public init(provider: Provider, windows: [AIUsageWindow], errorMessage: String? = nil) { self.provider = provider; self.windows = windows; self.errorMessage = errorMessage }
}

public struct AIUsageSnapshot: Equatable, Sendable {
    public let checkedAt: Date
    public let providers: [AIUsageProviderStatus]
    public init(checkedAt: Date, providers: [AIUsageProviderStatus]) { self.checkedAt = checkedAt; self.providers = providers }
}

public struct AIUsageResponseParser: Sendable {
    public init() {}
    public func parseClaude(_ data: Data) throws -> [AIUsageWindow] {
        let root = try object(data)
        if let limits = root["limits"] as? [[String: Any]] {
            let parsed = limits.compactMap { limit -> AIUsageWindow? in
                let label: String
                switch limit["kind"] as? String { case "session": label = "5시간"; case "weekly_all": label = "주간"; default: return nil }
                return window(limit, label: label, keys: ["percent", "utilization", "utilization_pct", "used_percentage"])
            }
            if !parsed.isEmpty { return parsed }
        }
        return [window(root["five_hour"], label: "5시간", keys: percentageKeys), window(root["seven_day"], label: "주간", keys: percentageKeys)].compactMap { $0 }
    }
    public func parseCodex(_ data: Data) throws -> [AIUsageWindow] {
        let root = try object(data)
        guard let rateLimit = root["rate_limit"] as? [String: Any] else { return [] }
        return [window(rateLimit["primary_window"], label: "5시간", keys: percentageKeys), window(rateLimit["secondary_window"], label: "주간", keys: percentageKeys)].compactMap { $0 }
    }
    private let percentageKeys = ["used_percent", "used_percentage", "utilization", "usedPercent", "percent"]
    private func object(_ data: Data) throws -> [String: Any] { guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIUsageMonitorError.invalidResponse }; return value }
    private func window(_ value: Any?, label: String, keys: [String]) -> AIUsageWindow? {
        guard let value = value as? [String: Any] else { return nil }
        let percentage = keys.lazy.compactMap { number(value[$0]) }.first ?? number(value["remaining_percentage"]).map { 100 - $0 }
        let resetsAt = date(value["reset_at"] ?? value["resets_at"] ?? value["resetsAt"])
        guard percentage != nil || resetsAt != nil else { return nil }
        return .init(label: label, usedPercentage: percentage.map { min(100, max(0, $0)) }, resetsAt: resetsAt)
    }
    private func number(_ value: Any?) -> Double? { if let value = value as? NSNumber { return value.doubleValue }; if let value = value as? String { return Double(value) }; return nil }
    private func date(_ value: Any?) -> Date? { if let seconds = number(value) { return Date(timeIntervalSince1970: seconds) }; guard let string = value as? String else { return nil }; return ISO8601DateFormatter().date(from: string) }
}

public enum AIUsageMonitorError: Error, Equatable, Sendable { case credentialsUnavailable; case invalidResponse; case requestFailed(Int) }

public actor AIUsageMonitor {
    public static let refreshInterval: TimeInterval = 10 * 60
    private let session: URLSession
    private let parser: AIUsageResponseParser
    private let now: @Sendable () -> Date
    private var cached: AIUsageSnapshot?
    private let cacheDuration: TimeInterval
    public init(session: URLSession = .shared, parser: AIUsageResponseParser = .init(), cacheDuration: TimeInterval = AIUsageMonitor.refreshInterval, now: @escaping @Sendable () -> Date = Date.init) { self.session = session; self.parser = parser; self.cacheDuration = cacheDuration; self.now = now }
    public func snapshot() async -> AIUsageSnapshot {
        let checkedAt = now()
        if let cached, checkedAt.timeIntervalSince(cached.checkedAt) < cacheDuration { return cached }
        async let claude = loadClaude(); async let codex = loadCodex()
        let snapshot = await AIUsageSnapshot(checkedAt: checkedAt, providers: [claude, codex]); cached = snapshot; return snapshot
    }
    private func loadClaude() async -> AIUsageProviderStatus {
        do {
            let credentials = try claudeCredentials()
            guard let oauth = credentials["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else { throw AIUsageMonitorError.credentialsUnavailable }
            let data = try await request(URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: ["Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20"])
            let windows = try parser.parseClaude(data); return .init(provider: .claude, windows: windows, errorMessage: windows.isEmpty ? "사용량 정보 없음" : nil)
        } catch { return .init(provider: .claude, windows: [], errorMessage: safeMessage(error)) }
    }
    private func loadCodex() async -> AIUsageProviderStatus {
        do {
            let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            guard let tokens = root?["tokens"] as? [String: Any], let token = tokens["access_token"] as? String else { throw AIUsageMonitorError.credentialsUnavailable }
            var headers = ["Authorization": "Bearer \(token)", "openai-beta": "codex-1", "originator": "Codex Desktop"]
            if let account = tokens["account_id"] as? String { headers["chatgpt-account-id"] = account }
            let data = try await request(URL(string: "https://chatgpt.com/backend-api/wham/usage")!, headers: headers)
            let windows = try parser.parseCodex(data); return .init(provider: .codex, windows: windows, errorMessage: windows.isEmpty ? "사용량 정보 없음" : nil)
        } catch { return .init(provider: .codex, windows: [], errorMessage: safeMessage(error)) }
    }
    private func request(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 10); headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw AIUsageMonitorError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0) }; return data
    }
    private func claudeCredentials() throws -> [String: Any] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIUsageMonitorError.credentialsUnavailable }; return object
    }
    private func safeMessage(_ error: Error) -> String { if case AIUsageMonitorError.requestFailed(let status) = error { return "조회 실패 (\(status))" }; if error is CocoaError || error is AIUsageMonitorError { return "로그인 정보 없음" }; return "조회 실패" }
}
