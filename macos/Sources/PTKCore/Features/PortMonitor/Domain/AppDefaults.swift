public struct PortPreset: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let expression: String
    public let detail: String

    public init(id: String, title: String, expression: String, detail: String) {
        self.id = id
        self.title = title
        self.expression = expression
        self.detail = detail
    }
}

public enum AppDefaults {
    public static let appName = "PTK"
    public static let defaultWatchedPortsExpression = "3000-3009,5173-5182,4200-4209,8080-8089"
    public static let portPresets = [
        PortPreset(
            id: "full-stack",
            title: "Full Stack",
            expression: defaultWatchedPortsExpression,
            detail: "Frontend + Next + API"
        ),
        PortPreset(
            id: "frontend",
            title: "Frontend",
            expression: "3000-3009,5173-5182",
            detail: "Next + Vite"
        ),
        PortPreset(
            id: "api",
            title: "API",
            expression: "8000-8009,8080-8089",
            detail: "Local backend"
        ),
        PortPreset(
            id: "data",
            title: "Data",
            expression: "3306,5432,6379,27017",
            detail: "DB + cache"
        )
    ]
    public static let maxPortCount = 5_000
    public static let defaultRefreshInterval: RefreshInterval = .defaultValue
}
