import Foundation
import Testing
import UserNotifications
@testable import PTKApp
import PTKCore

@Suite("User notification client")
@MainActor
struct UserNotificationClientTests {
    private func candidate(
        port: UInt16 = 3000,
        kind: PortChangeKind = .opened,
        pid: Int? = 123,
        processName: String? = "node"
    ) -> PortChangeNotificationCandidate {
        PortChangeNotificationCandidate(port: port, kind: kind, pid: pid, processName: processName)
    }
    @Test func verifiedOpenPayloadIncludesExistingProcessDetail() {
        let payload = PortChangeNotificationPayload(candidate: candidate(processName: "/usr/local/bin/node"))!

        #expect(payload.title == "PTK")
        #expect(payload.body == "Port 3000 열림 · node · PID 123")
        #expect(payload.categoryIdentifier == "ptk.port-change")
    }

    @Test func builderUsesUniqueInjectedIdentifiersAndPropertyListMetadata() {
        let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let one = try! PortChangeUserNotificationRequestBuilder(nextUUID: { first }).makeRequest(for: candidate())
        let two = try! PortChangeUserNotificationRequestBuilder(nextUUID: { second }).makeRequest(for: candidate())
        let metadata = one.payload.metadata.propertyListUserInfo

        #expect(one.identifier == "ptk.port-change.11111111-1111-1111-1111-111111111111")
        #expect(two.identifier == "ptk.port-change.22222222-2222-2222-2222-222222222222")
        #expect(one.identifier != two.identifier)
        #expect(metadata["ptkNotificationType"] as? String == "port-change")
        #expect(metadata["port"] as? NSNumber == NSNumber(value: 3000))
        #expect(metadata["kind"] as? String == "opened")
        #expect(PropertyListSerialization.propertyList(metadata, isValidFor: .binary))
    }

    @Test func classifiesExactMetadataAndDefaultActionsOnly() {
        let metadata = PortChangeNotificationMetadata(port: 3000, kind: .opened)!.propertyListUserInfo

        #expect(UserNotificationClient.hasPortChangeMetadata(metadata))
        #expect(UserNotificationClient.isPortChangeDefaultAction(
            categoryIdentifier: "ptk.port-change",
            userInfo: metadata,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        #expect(UserNotificationClient.isPortChangeDefaultAction(
            categoryIdentifier: "foreign",
            userInfo: metadata,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ) == false)
        #expect(UserNotificationClient.isPortChangeDefaultAction(
            categoryIdentifier: "ptk.port-change",
            userInfo: metadata,
            actionIdentifier: UNNotificationDismissActionIdentifier
        ) == false)
        #expect(UserNotificationClient.isPortChangeDefaultAction(
            categoryIdentifier: "ptk.port-change",
            userInfo: [:],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ) == false)
    }

    @Test func nativeClientSeamInstallsDelegateUsesPermissionAndRejectsStoppedDelivery() async {
        let center = NotificationCenterSpy()
        center.status = .denied
        let client = UserNotificationClient(center: center)

        #expect(center.delegate != nil)
        #expect(await client.notificationPermissionStatus() == .denied)
        client.stop()

        do {
            try await client.deliver(candidate())
            Issue.record("Stopped delivery must throw.")
        } catch is CancellationError {
        } catch {
            Issue.record("Stopped delivery threw the wrong error.")
        }
        #expect(center.requests.isEmpty)
        #expect(center.removeDelegateCount == 1)
    }

    @Test func stopClearsPendingSignalAndBlocksFutureRouting() {
        let router = PortChangeNotificationResponseRouter()
        var calls = 0

        router.routeDefaultAction()
        router.stop()
        router.attachPanelHandler { calls += 1 }
        router.routeDefaultAction()

        #expect(router.hasPendingSignal == false)
        #expect(calls == 0)
    }

    @Test(arguments: [
        (UNAuthorizationStatus.authorized, PortChangeNotificationPermissionStatus.authorized),
        (.provisional, .authorized),
        (.denied, .denied),
        (.notDetermined, .notDetermined)
    ])
    func mapsAuthorizationStatuses(_ status: UNAuthorizationStatus, _ expected: PortChangeNotificationPermissionStatus) {
        #expect(UserNotificationClient.permissionStatus(for: status) == expected)
    }

}

private enum ClientTestError: Error { case failed }


@MainActor
private final class NotificationCenterSpy: UserNotificationCenterClient {
    weak var delegate: UNUserNotificationCenterDelegate?
    var status: PortChangeNotificationPermissionStatus = .authorized
    var requests: [UNNotificationRequest] = []
    var removeDelegateCount = 0
    var permissionRequestCount = 0
    var shouldFailAdd = false

    func installDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }

    func removeDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        if self.delegate === delegate {
            self.delegate = nil
        }
        removeDelegateCount += 1
    }

    func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus {
        status
    }

    func requestNotificationPermission() async throws {
        permissionRequestCount += 1
    }

    func add(_ request: UNNotificationRequest) async throws {
        if shouldFailAdd { throw ClientTestError.failed }
        requests.append(request)
    }
}
