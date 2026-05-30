public struct PortStatus: Equatable, Sendable {
    public let port: UInt16
    public let isOpen: Bool
    public let pid: Int?
    public let processName: String?
    public let message: String?

    public init(
        port: UInt16,
        isOpen: Bool,
        pid: Int? = nil,
        processName: String? = nil,
        message: String? = nil
    ) {
        self.port = port
        self.isOpen = isOpen
        self.pid = pid
        self.processName = processName
        self.message = message
    }
}
