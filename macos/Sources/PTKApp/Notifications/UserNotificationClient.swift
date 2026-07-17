import Foundation
import PTKCore
import UserNotifications

public struct PortChangeNotificationMetadata: Equatable, Sendable {
    public static let categoryIdentifier = "ptk.port-change"
    public static let typeKey = "ptkNotificationType"
    public static let typeValue = "port-change"
    public static let portKey = "port"
    public static let kindKey = "kind"

    public let port: UInt16
    public let kind: PortChangeKind

    public init?(port: UInt16, kind: PortChangeKind) {
        guard kind == .opened || kind == .closed else { return nil }
        self.port = port
        self.kind = kind
    }

    public var propertyListUserInfo: [AnyHashable: Any] {
        [
            Self.typeKey: Self.typeValue,
            Self.portKey: NSNumber(value: port),
            Self.kindKey: kind.rawValue
        ]
    }
}

public struct PortChangeNotificationPayload: Equatable, Sendable {
    public let title: String
    public let body: String
    public let categoryIdentifier: String
    public let metadata: PortChangeNotificationMetadata

    public init?(candidate: PortChangeNotificationCandidate) {
        guard let metadata = PortChangeNotificationMetadata(port: candidate.port, kind: candidate.kind) else {
            return nil
        }
        title = "PTK"
        categoryIdentifier = PortChangeNotificationMetadata.categoryIdentifier
        self.metadata = metadata
        body = Self.body(for: candidate)
    }

    private static func body(for candidate: PortChangeNotificationCandidate) -> String {
        switch candidate.kind {
        case .opened:
            var parts = ["Port \(candidate.port) 열림"]
            if let processName = candidate.processName, !processName.isEmpty {
                parts.append(processName.ptkDisplayProcessName)
            }
            if let pid = candidate.pid, pid > 0 {
                parts.append("PID \(pid)")
            }
            return parts.joined(separator: " · ")
        case .closed:
            return "Port \(candidate.port) 닫힘"
        case .changed:
            preconditionFailure("Unsupported port change notification kind")
        }
    }
}

public struct PortChangeUserNotificationRequest: Equatable, Sendable {
    public let identifier: String
    public let payload: PortChangeNotificationPayload

    public init(identifier: String, payload: PortChangeNotificationPayload) {
        self.identifier = identifier
        self.payload = payload
    }
}

public enum PortChangeUserNotificationRequestBuilderError: Error, Equatable, Sendable {
    case unsupportedChangeKind
}

public struct PortChangeUserNotificationRequestBuilder: Sendable {
    private let nextUUID: @Sendable () -> UUID

    public init(nextUUID: @escaping @Sendable () -> UUID = UUID.init) {
        self.nextUUID = nextUUID
    }

    public func makeRequest(for candidate: PortChangeNotificationCandidate) throws -> PortChangeUserNotificationRequest {
        guard let payload = PortChangeNotificationPayload(candidate: candidate) else {
            throw PortChangeUserNotificationRequestBuilderError.unsupportedChangeKind
        }
        return PortChangeUserNotificationRequest(
            identifier: "ptk.port-change.\(nextUUID().uuidString)",
            payload: payload
        )
    }

    public func makeUNNotificationRequest(for candidate: PortChangeNotificationCandidate) throws -> UNNotificationRequest {
        let request = try makeRequest(for: candidate)
        let content = UNMutableNotificationContent()
        content.title = request.payload.title
        content.body = request.payload.body
        content.categoryIdentifier = request.payload.categoryIdentifier
        content.userInfo = request.payload.metadata.propertyListUserInfo
        return UNNotificationRequest(identifier: request.identifier, content: content, trigger: nil)
    }
}

@MainActor
public protocol UserNotificationCenterClient: AnyObject {
    func installDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func removeDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus
    func requestNotificationPermission() async throws
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
public final class NativeUserNotificationCenterClient: UserNotificationCenterClient {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func installDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }

    public func removeDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        if center.delegate === delegate {
            center.delegate = nil
        }
    }

    public func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus {
        UserNotificationClient.permissionStatus(for: await center.notificationSettings().authorizationStatus)
    }

    public func requestNotificationPermission() async throws {
        _ = try await center.requestAuthorization(options: [.alert])
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}

@MainActor
public final class PortChangeNotificationResponseRouter {
    private var panelHandler: (@MainActor @Sendable () -> Void)?
    private var hasPendingPanelSignal = false
    private var isRunning = true

    public init() {}

    public func attachPanelHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        guard isRunning else { return }
        panelHandler = handler
        if hasPendingPanelSignal {
            hasPendingPanelSignal = false
            handler()
        }
    }

    public func detachPanelHandler() {
        panelHandler = nil
    }

    public func routeDefaultAction() {
        guard isRunning else { return }
        if let panelHandler {
            panelHandler()
        } else {
            hasPendingPanelSignal = true
        }
    }

    public func stop() {
        isRunning = false
        hasPendingPanelSignal = false
        panelHandler = nil
    }

    public var hasPendingSignal: Bool { hasPendingPanelSignal }
}

@MainActor
public final class UserNotificationClient: NSObject, PortChangeNotificationPermissionProviding, PortChangeNotificationDelivering, UNUserNotificationCenterDelegate {
    private let center: any UserNotificationCenterClient
    private let requestBuilder: PortChangeUserNotificationRequestBuilder
    private let responseRouter = PortChangeNotificationResponseRouter()
    private var isRunning = true

    public init(
        center: any UserNotificationCenterClient = NativeUserNotificationCenterClient(),
        requestBuilder: PortChangeUserNotificationRequestBuilder = .init()
    ) {
        self.center = center
        self.requestBuilder = requestBuilder
        super.init()
        center.installDelegate(self)
    }


    public func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus {
        await center.notificationPermissionStatus()
    }

    public func requestNotificationPermission() async throws {
        try await center.requestNotificationPermission()
    }

    public func deliver(_ candidate: PortChangeNotificationCandidate) async throws {
        guard isRunning else { throw CancellationError() }
        let request = try requestBuilder.makeUNNotificationRequest(for: candidate)
        try await center.add(request)
    }

    public func attachPanelHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        responseRouter.attachPanelHandler(handler)
    }

    public func detachPanelHandler() {
        responseRouter.detachPanelHandler()
    }

    public func stop() {
        isRunning = false
        responseRouter.stop()
        center.removeDelegate(self)
    }

    nonisolated public static func permissionStatus(for status: UNAuthorizationStatus) -> PortChangeNotificationPermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }

    nonisolated public static func hasPortChangeMetadata(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let type = userInfo[PortChangeNotificationMetadata.typeKey] as? String,
              type == PortChangeNotificationMetadata.typeValue,
              let port = userInfo[PortChangeNotificationMetadata.portKey] as? NSNumber,
              CFGetTypeID(port) != CFBooleanGetTypeID(),
              let portValue = UInt16(exactly: port.uint64Value),
              NSNumber(value: portValue) == port,
              let kind = userInfo[PortChangeNotificationMetadata.kindKey] as? String,
              let portChangeKind = PortChangeKind(rawValue: kind),
              portChangeKind == .opened || portChangeKind == .closed else { return false }
        return true
    }

    nonisolated public static func isPortChangeDefaultAction(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String
    ) -> Bool {
        categoryIdentifier == PortChangeNotificationMetadata.categoryIdentifier
            && hasPortChangeMetadata(userInfo)
            && actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    nonisolated public static func foregroundPresentationOptions(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> UNNotificationPresentationOptions {
        guard categoryIdentifier == PortChangeNotificationMetadata.categoryIdentifier,
              hasPortChangeMetadata(userInfo) else { return [] }
        return [.banner, .list]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentationOptions(
            categoryIdentifier: notification.request.content.categoryIdentifier,
            userInfo: notification.request.content.userInfo
        ))
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        handleResponse(
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            completionHandler: completionHandler
        )
    }

    nonisolated func handleResponse(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        let shouldRoute = Self.isPortChangeDefaultAction(
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo,
            actionIdentifier: actionIdentifier
        )
        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard shouldRoute else { return }
            self?.responseRouter.routeDefaultAction()
        }
    }
}
