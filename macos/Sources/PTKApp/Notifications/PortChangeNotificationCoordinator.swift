import Foundation
import PTKCore

public enum PortChangeNotificationPermissionStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unknown
}

@MainActor
public protocol PortChangeNotificationPermissionProviding: AnyObject {
    func notificationPermissionStatus() async -> PortChangeNotificationPermissionStatus
    func requestNotificationPermission() async throws
}

@MainActor
public protocol PortChangeNotificationDelivering: AnyObject {
    func deliver(_ candidate: PortChangeNotificationCandidate) async throws
}

@MainActor
public protocol PortChangeNotificationClock: AnyObject {
    var monotonicTime: TimeInterval { get }
}

@MainActor
public protocol PortChangeNotificationEligibilityProviding: AnyObject {
    var notificationsEnabled: Bool { get }
    var selectedNotificationPorts: Set<UInt16> { get }
    var notificationEligibilityRevision: UInt64 { get }
}


public struct PortChangeNotificationCandidate: Equatable, Sendable {
    public let port: UInt16
    public let kind: PortChangeKind
    public let pid: Int?
    public let processName: String?

    public init(port: UInt16, kind: PortChangeKind, pid: Int?, processName: String?) {
        self.port = port
        self.kind = kind
        self.pid = pid
        self.processName = processName
    }
}

public struct PortChangeNotificationSnapshot: Sendable {
    public let generation: UInt64
    public let watchedEpoch: UInt64
    public let watchedPorts: Set<UInt16>
    public let statuses: [PortStatus]

    public init(generation: UInt64, watchedEpoch: UInt64, watchedPorts: Set<UInt16>, statuses: [PortStatus]) {
        self.generation = generation
        self.watchedEpoch = watchedEpoch
        self.watchedPorts = watchedPorts
        self.statuses = statuses
    }
}

@MainActor
public final class PortChangeNotificationCoordinator {
    private enum ReliableState: Equatable {
        case closed
        case openVerified(pid: Int, processName: String)
        case openPIDOnly(pid: Int)

        init?(_ status: PortStatus) {
            guard status.isOpen else {
                self = .closed
                return
            }
            if let identity = status.verifiedIdentity {
                self = .openVerified(pid: identity.pid, processName: identity.processName)
                return
            }
            if case .unavailable(.processNameUnavailable(let pid))? = status.identityState, pid > 0 {
                self = .openPIDOnly(pid: pid)
                return
            }
            return nil
        }

        var candidateIdentity: (Int?, String?) {
            switch self {
            case .closed: (nil, nil)
            case .openVerified(let pid, let processName): (pid, processName)
            case .openPIDOnly(let pid): (pid, nil)
            }
        }
    }

    private struct PermissionRequest {
        let lifecycleEpoch: UInt64
        let eligibilityRevision: UInt64
        let ownershipEpoch: UInt64
        let task: Task<PermissionResolution, Never>
    }

    private struct PermissionResolution {
        let status: PortChangeNotificationPermissionStatus
        let error: (any Error)?
    }

    private struct QueuedCandidate {
        let candidate: PortChangeNotificationCandidate
        let lifecycleEpoch: UInt64
        let watchedEpoch: UInt64
        let eligibilityRevision: UInt64
    }

    private let permission: any PortChangeNotificationPermissionProviding
    private let delivery: any PortChangeNotificationDelivering
    private let clock: any PortChangeNotificationClock
    private let eligibility: any PortChangeNotificationEligibilityProviding

    public private(set) var permissionStatus: PortChangeNotificationPermissionStatus = .unknown
    public private(set) var lastPermissionRequestError: (any Error)?
    public private(set) var isRunning = true
    public private(set) var generation: UInt64 = 0
    public private(set) var watchedEpoch: UInt64 = 0
    public private(set) var watchedPorts: Set<UInt16>

    private var lifecycleEpoch: UInt64 = 0
    private var baselines: [UInt16: ReliableState] = [:]
    private var lastDelivered: [UInt16: (kind: PortChangeKind, time: TimeInterval)] = [:]
    private var queue: [QueuedCandidate] = []
    private var isDraining = false
    private var drainIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var permissionRequest: PermissionRequest?
    private var permissionRequestOwnershipEpoch: UInt64 = 0
    private var permissionPublicationEpoch: UInt64 = 0

    public init(
        watchedPorts: Set<UInt16>,
        permission: any PortChangeNotificationPermissionProviding,
        delivery: any PortChangeNotificationDelivering,
        clock: any PortChangeNotificationClock,
        eligibility: any PortChangeNotificationEligibilityProviding
    ) {
        self.watchedPorts = watchedPorts
        self.permission = permission
        self.delivery = delivery
        self.clock = clock
        self.eligibility = eligibility
    }

    public func start() {
        lifecycleEpoch &+= 1
        isRunning = true
    }

    public func stop() {
        lifecycleEpoch &+= 1
        isRunning = false
        queue.removeAll()
        permissionRequest = nil
    }

    /// Commits the semantic watch set. Removed ports lose history; re-added ports start baseline-only.
    public func commitWatchedPorts(_ ports: Set<UInt16>) {
        guard ports != watchedPorts else { return }
        let removed = watchedPorts.subtracting(ports)
        for port in removed {
            baselines.removeValue(forKey: port)
            lastDelivered.removeValue(forKey: port)
        }
        watchedPorts = ports
        watchedEpoch &+= 1
        queue.removeAll()
    }

    /// Sets the accepted scan generation and observes it when it still matches the committed watch set.
    public func accept(_ snapshot: PortChangeNotificationSnapshot) {
        generation = snapshot.generation
        observe(snapshot)
    }

    public func observe(_ snapshot: PortChangeNotificationSnapshot) {
        guard isRunning,
              snapshot.generation == generation,
              snapshot.watchedEpoch == watchedEpoch,
              snapshot.watchedPorts == watchedPorts,
              isValid(snapshot) else { return }

        for status in snapshot.statuses where watchedPorts.contains(status.port) {
            guard let current = ReliableState(status) else { continue }
            let previous = baselines[status.port]
            baselines[status.port] = current
            guard let previous, previous != current,
                  eligibility.notificationsEnabled,
                  eligibility.selectedNotificationPorts.contains(status.port),
                  watchedPorts.contains(status.port),
                  let kind = changeKind(from: previous, to: current) else { continue }
            let identity = current.candidateIdentity
            queue.append(QueuedCandidate(
                candidate: PortChangeNotificationCandidate(port: status.port, kind: kind, pid: identity.0, processName: identity.1),
                lifecycleEpoch: lifecycleEpoch,
                watchedEpoch: watchedEpoch,
                eligibilityRevision: eligibility.notificationEligibilityRevision
            ))
        }
        beginDrainIfNeeded()
    }

    public func refreshPermissionStatus() async {
        let lifecycle = lifecycleEpoch
        let eligibilityRevision = eligibility.notificationEligibilityRevision
        permissionPublicationEpoch &+= 1
        let publicationEpoch = permissionPublicationEpoch
        let status = await permission.notificationPermissionStatus()
        guard isPermissionPublicationValid(
            lifecycleEpoch: lifecycle,
            eligibilityRevision: eligibilityRevision,
            publicationEpoch: publicationEpoch
        ) else { return }
        permissionStatus = status
    }

    /// Requests only from a fresh `.notDetermined` reading. Concurrent callers share only the current valid request.
    public func requestPermissionIfNeeded() async {
        guard isRunning, eligibility.notificationsEnabled else { return }

        let lifecycle = lifecycleEpoch
        let eligibilityRevision = eligibility.notificationEligibilityRevision
        if let request = permissionRequest,
           request.lifecycleEpoch == lifecycle,
           request.eligibilityRevision == eligibilityRevision {
            let resolution = await request.task.value
            finishPermissionRequest(request, resolution: resolution)
            return
        }

        permissionPublicationEpoch &+= 1
        let permission = permission
        let task = Task { @MainActor [weak self, permission] in
            let current = await permission.notificationPermissionStatus()
            guard current == .notDetermined else {
                return PermissionResolution(status: current, error: nil)
            }
            guard let self,
                  self.isPermissionRequestValid(
                    lifecycleEpoch: lifecycle,
                    eligibilityRevision: eligibilityRevision
                  ) else {
                return PermissionResolution(status: current, error: nil)
            }

            do {
                try await permission.requestNotificationPermission()
                return PermissionResolution(
                    status: await permission.notificationPermissionStatus(),
                    error: nil
                )
            } catch {
                return PermissionResolution(
                    status: await permission.notificationPermissionStatus(),
                    error: error
                )
            }
        }
        permissionRequestOwnershipEpoch &+= 1
        let request = PermissionRequest(
            lifecycleEpoch: lifecycle,
            eligibilityRevision: eligibilityRevision,
            ownershipEpoch: permissionRequestOwnershipEpoch,
            task: task
        )
        permissionRequest = request
        finishPermissionRequest(request, resolution: await task.value)
    }

    private func finishPermissionRequest(
        _ request: PermissionRequest,
        resolution: PermissionResolution
    ) {
        guard permissionRequest?.ownershipEpoch == request.ownershipEpoch else { return }
        permissionRequest = nil
        guard isPermissionRequestValid(
            lifecycleEpoch: request.lifecycleEpoch,
            eligibilityRevision: request.eligibilityRevision
        ) else { return }
        permissionPublicationEpoch &+= 1
        permissionStatus = resolution.status
        lastPermissionRequestError = resolution.error
    }

    private func isPermissionRequestValid(
        lifecycleEpoch: UInt64,
        eligibilityRevision: UInt64
    ) -> Bool {
        isRunning
            && lifecycleEpoch == self.lifecycleEpoch
            && eligibility.notificationsEnabled
            && eligibilityRevision == eligibility.notificationEligibilityRevision
    }

    private func isPermissionPublicationValid(
        lifecycleEpoch: UInt64,
        eligibilityRevision: UInt64,
        publicationEpoch: UInt64
    ) -> Bool {
        isPermissionRequestValid(
            lifecycleEpoch: lifecycleEpoch,
            eligibilityRevision: eligibilityRevision
        ) && publicationEpoch == permissionPublicationEpoch
    }

    private func beginDrainIfNeeded() {
        guard !isDraining, !queue.isEmpty else { return }
        isDraining = true
        drainNext()
    }
    func waitForDrainIdle() async {
        guard isDraining else { return }
        await withCheckedContinuation { continuation in
            drainIdleWaiters.append(continuation)
        }
    }


    private func drainNext() {
        guard !queue.isEmpty else {
            isDraining = false
            let waiters = drainIdleWaiters
            drainIdleWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            return
        }

        let queued = queue.removeFirst()
        guard isEligible(queued) else {
            drainNext()
            return
        }

        let permission = permission
        permissionPublicationEpoch &+= 1
        let publicationEpoch = permissionPublicationEpoch
        Task { @MainActor [weak self, permission] in
            let status = await permission.notificationPermissionStatus()
            guard let self, self.isEligible(queued) else {
                self?.drainNext()
                return
            }
            if publicationEpoch == self.permissionPublicationEpoch {
                self.permissionStatus = status
            }
            guard status == .authorized || status == .provisional else {
                self.drainNext()
                return
            }
            let now = self.clock.monotonicTime
            if let last = self.lastDelivered[queued.candidate.port],
               last.kind == queued.candidate.kind,
               now - last.time < 10 {
                self.drainNext()
                return
            }

            let delivery = self.delivery
            Task { @MainActor [weak self, delivery] in
                do {
                    try await delivery.deliver(queued.candidate)
                } catch {
                    self?.drainNext()
                    return
                }
                guard let self,
                      self.isRunning,
                      queued.lifecycleEpoch == self.lifecycleEpoch else {
                    self?.drainNext()
                    return
                }
                self.lastDelivered[queued.candidate.port] = (queued.candidate.kind, self.clock.monotonicTime)
                self.drainNext()
            }
        }
    }

    private func isEligible(_ queued: QueuedCandidate) -> Bool {
        isRunning
            && queued.lifecycleEpoch == lifecycleEpoch
            && queued.watchedEpoch == watchedEpoch
            && queued.eligibilityRevision == eligibility.notificationEligibilityRevision
            && watchedPorts.contains(queued.candidate.port)
            && eligibility.notificationsEnabled
            && eligibility.selectedNotificationPorts.contains(queued.candidate.port)
    }

    private func isValid(_ snapshot: PortChangeNotificationSnapshot) -> Bool {
        let ports = snapshot.statuses.map(\.port)
        return Set(ports).count == ports.count && Set(ports).isSubset(of: snapshot.watchedPorts)
    }

    private func changeKind(from previous: ReliableState, to current: ReliableState) -> PortChangeKind? {
        switch (previous, current) {
        case (.closed, .openVerified), (.closed, .openPIDOnly):
            return .opened
        case (.openVerified, .closed), (.openPIDOnly, .closed):
            return .closed
        default:
            return nil
        }
    }
}
