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

    @Test func pidOnlyOpenPayloadDoesNotInventAProcessName() {
        let payload = PortChangeNotificationPayload(candidate: candidate(pid: 456, processName: nil))!

        #expect(payload.body == "Port 3000 열림 · PID 456")
        #expect(payload.body.contains("node") == false)
    }

    @Test func closedPayloadHasNoStaleProcessDetail() {
        let payload = PortChangeNotificationPayload(candidate: candidate(kind: .closed, pid: 123, processName: "node"))!

        #expect(payload.body == "Port 3000 닫힘")
        #expect(payload.body.contains("PID") == false)
        #expect(payload.body.contains("node") == false)
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

    @Test func nativeRequestUsesImmediateAlertWithoutTrigger() {
        let uuid = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let request = try! PortChangeUserNotificationRequestBuilder(nextUUID: { uuid }).makeUNNotificationRequest(for: candidate())

        #expect(request.identifier == "ptk.port-change.33333333-3333-3333-3333-333333333333")
        #expect(request.trigger == nil)
        #expect(request.content.title == "PTK")
        #expect(request.content.body == "Port 3000 열림 · node · PID 123")
        #expect(request.content.categoryIdentifier == "ptk.port-change")
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

    @Test func classifiesExactMetadataAndDefaultActionsOnly() {
        let metadata = PortChangeNotificationMetadata(port: 3000, kind: .opened)!.propertyListUserInfo
        let booleanPort: [AnyHashable: Any] = [
            "ptkNotificationType": "port-change",
            "port": NSNumber(value: true),
            "kind": "opened"
        ]
        let fractionalPort: [AnyHashable: Any] = [
            "ptkNotificationType": "port-change",
            "port": NSNumber(value: 3000.5),
            "kind": "opened"
        ]
        let changedKind: [AnyHashable: Any] = [
            "ptkNotificationType": "port-change",
            "port": NSNumber(value: 3000),
            "kind": "changed"
        ]
        let negativePort: [AnyHashable: Any] = [
            "ptkNotificationType": "port-change",
            "port": NSNumber(value: -1),
            "kind": "opened"
        ]
        let overflowPort: [AnyHashable: Any] = [
            "ptkNotificationType": "port-change",
            "port": NSNumber(value: 65_536),
            "kind": "opened"
        ]
        let unknownKind: [AnyHashable: Any] = [
            "ptkNotificationType": "port-change",
            "port": NSNumber(value: 3000),
            "kind": "other"
        ]

        #expect(UserNotificationClient.hasPortChangeMetadata(metadata))
        #expect(UserNotificationClient.hasPortChangeMetadata(booleanPort) == false)
        #expect(UserNotificationClient.hasPortChangeMetadata(fractionalPort) == false)
        #expect(UserNotificationClient.hasPortChangeMetadata(changedKind) == false)
        #expect(UserNotificationClient.hasPortChangeMetadata(negativePort) == false)
        #expect(UserNotificationClient.hasPortChangeMetadata(overflowPort) == false)
        #expect(UserNotificationClient.hasPortChangeMetadata(unknownKind) == false)
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
        #expect(UserNotificationClient.isPortChangeDefaultAction(
            categoryIdentifier: "ptk.port-change",
            userInfo: metadata,
            actionIdentifier: "custom"
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
    @Test func clientForwardsPermissionAndNativeAddFailuresWithoutSubmittingChangedCandidates() async {
        let center = NotificationCenterSpy()
        let client = UserNotificationClient(center: center)

        try! await client.requestNotificationPermission()
        try! await client.deliver(candidate())
        #expect(center.permissionRequestCount == 1)
        #expect(center.requests.count == 1)
        #expect(center.requests[0].content.userInfo["kind"] as? String == "opened")

        do {
            try await client.deliver(candidate(kind: .changed))
            Issue.record("Changed candidates must be rejected before native add.")
        } catch let error as PortChangeUserNotificationRequestBuilderError {
            #expect(error == .unsupportedChangeKind)
        } catch {
            Issue.record("Changed candidate threw the wrong error.")
        }
        #expect(center.requests.count == 1)

        center.shouldFailAdd = true
        do {
            try await client.deliver(candidate())
            Issue.record("Native add failures must propagate.")
        } catch ClientTestError.failed {
        } catch {
            Issue.record("Native add threw the wrong error.")
        }
    }


    @Test func foregroundPresentationIsBannerAndListOnlyForExactMetadata() {
        let metadata = PortChangeNotificationMetadata(port: 3000, kind: .opened)!.propertyListUserInfo

        #expect(UserNotificationClient.foregroundPresentationOptions(
            categoryIdentifier: "ptk.port-change",
            userInfo: metadata
        ) == [.banner, .list])
        #expect(UserNotificationClient.foregroundPresentationOptions(
            categoryIdentifier: "foreign",
            userInfo: metadata
        ).isEmpty)
        #expect(UserNotificationClient.foregroundPresentationOptions(
            categoryIdentifier: "ptk.port-change",
            userInfo: [:]
        ).isEmpty)
    }

    @Test func pendingDefaultClicksCoalesceAndDrainOnceWhenHandlerAttaches() {
        let router = PortChangeNotificationResponseRouter()
        var calls = 0

        router.routeDefaultAction()
        router.routeDefaultAction()
        #expect(router.hasPendingSignal)

        router.attachPanelHandler { calls += 1 }
        #expect(calls == 1)
        #expect(router.hasPendingSignal == false)

        router.detachPanelHandler()
        router.attachPanelHandler { calls += 1 }
        #expect(calls == 1)
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
    @Test func delegateResponseHandlingRoutesOnlyValidClicksAndCompletesOnce() async {
        let center = NotificationCenterSpy()
        let client = UserNotificationClient(center: center)
        let metadata = PortChangeNotificationMetadata(port: 3000, kind: .opened)!.propertyListUserInfo
        let completions = CompletionSpy()
        var panelCalls = 0

        client.handleResponse(
            categoryIdentifier: PortChangeNotificationMetadata.categoryIdentifier,
            userInfo: metadata,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            completionHandler: { Task { await completions.complete() } }
        )
        await completions.wait(for: 1)
        client.attachPanelHandler { panelCalls += 1 }

        #expect(panelCalls == 1)
        let firstCompletionCount = await completions.count
        #expect(firstCompletionCount == 1)

        client.handleResponse(
            categoryIdentifier: "foreign",
            userInfo: metadata,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            completionHandler: { Task { await completions.complete() } }
        )
        await completions.wait(for: 2)

        client.stop()
        client.handleResponse(
            categoryIdentifier: PortChangeNotificationMetadata.categoryIdentifier,
            userInfo: metadata,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            completionHandler: { Task { await completions.complete() } }
        )
        await completions.wait(for: 3)

        #expect(panelCalls == 1)
        let finalCompletionCount = await completions.count
        #expect(finalCompletionCount == 3)
    }

    @Test func delegateResponseCompletionDoesNotRetainDeallocatedClient() async {
        let center = NotificationCenterSpy()
        let metadata = PortChangeNotificationMetadata(port: 3000, kind: .opened)!.propertyListUserInfo
        let completions = CompletionSpy()
        weak var weakClient: UserNotificationClient?

        do {
            var client: UserNotificationClient? = UserNotificationClient(center: center)
            weakClient = client
            client?.handleResponse(
                categoryIdentifier: PortChangeNotificationMetadata.categoryIdentifier,
                userInfo: metadata,
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                completionHandler: { Task { await completions.complete() } }
            )
            client = nil
        }

        await completions.wait(for: 1)
        #expect(weakClient == nil)
        let deallocationCompletionCount = await completions.count
        #expect(deallocationCompletionCount == 1)
    }
}
private actor CompletionSpy {
    private var completed = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var count: Int { completed }

    func complete() {
        completed += 1
        let ready = waiters.filter { $0.target <= completed }
        waiters.removeAll { $0.target <= completed }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    func wait(for target: Int) async {
        guard completed < target else { return }
        await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
        }
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
