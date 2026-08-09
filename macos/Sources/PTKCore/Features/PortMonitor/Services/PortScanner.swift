import Darwin
import Foundation

public protocol SocketConnecting: Sendable {
    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool
}

public extension SocketConnecting {
    func isListeningOnLocalhost(port: UInt16, timeout: TimeInterval) -> Bool {
        isListeningOnLocalhost(
            port: port,
            timeout: timeout,
            now: { ProcessInfo.processInfo.systemUptime }
        )
    }
}

extension SocketConnecting {
    func isListeningOnLocalhost(
        port: UInt16,
        timeout: TimeInterval,
        now: @Sendable () -> TimeInterval
    ) -> Bool {
        let startedAt = now()
        let deadline = startedAt + max(timeout, 0)
        let ipv4Timeout = max((deadline - startedAt) / 2, 0)

        if ipv4Timeout > 0,
           isListening(host: "127.0.0.1", port: port, timeout: ipv4Timeout) {
            return true
        }

        let ipv6Timeout = max(deadline - now(), 0)
        guard ipv6Timeout > 0 else { return false }
        return isListening(host: "::1", port: port, timeout: ipv6Timeout)
    }
}

public struct TCPPortConnector: SocketConnecting {
    public init() {}

    public func isListening(host: String, port: UInt16, timeout: TimeInterval = 0.2) -> Bool {
        var ipv4Address = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4Address) }) == 1 {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = ipv4Address
            return connect(
                family: AF_INET,
                address: &address,
                addressSize: MemoryLayout<sockaddr_in>.size,
                timeout: timeout
            )
        }

        var ipv6Address = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6Address) }) == 1 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = ipv6Address
            return connect(
                family: AF_INET6,
                address: &address,
                addressSize: MemoryLayout<sockaddr_in6>.size,
                timeout: timeout
            )
        }

        return false
    }

    private func connect<Address>(
        family: Int32,
        address: inout Address,
        addressSize: Int,
        timeout: TimeInterval
    ) -> Bool {
        guard timeout.isFinite, timeout > 0 else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let fd = socket(family, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return false
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(addressSize))
            }
        }
        let connectError = errno
        if result == 0 || connectError == EISCONN { return true }
        let isPending = connectError == EINPROGRESS
            || connectError == EALREADY
            || connectError == EINTR
        guard isPending else { return false }

        return waitForConnection(fd: fd, deadline: deadline)
    }

    private func waitForConnection(fd: Int32, deadline: TimeInterval) -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)

        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return false }
            let milliseconds = Int32(
                min(ceil(remaining * 1_000), Double(Int32.max))
            )
            let result = Darwin.poll(&descriptor, 1, max(milliseconds, 1))
            if result > 0 {
                var socketError: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard Darwin.getsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_ERROR,
                    &socketError,
                    &length
                ) == 0 else {
                    return false
                }
                return socketError == 0
            }
            if result == 0 || errno != EINTR {
                return false
            }
        }
    }
}

public struct PortScanner: Sendable {
    private let connector: any SocketConnecting
    private let lookup: ProcessLookup
    private let timeout: TimeInterval

    public init(
        connector: any SocketConnecting = TCPPortConnector(),
        lookup: ProcessLookup = ProcessLookup(),
        timeout: TimeInterval = 0.2
    ) {
        self.connector = connector
        self.lookup = lookup
        self.timeout = max(timeout, 0.05)
    }

    public func scan(ports: [UInt16]) -> [PortStatus] {
        let snapshotResult = Result { try lookup.listeningSnapshot() }

        return ports.map { port in
            guard connector.isListeningOnLocalhost(port: port, timeout: timeout) else {
                return PortStatus(port: port, isOpen: false, identityState: nil)
            }

            let resolvedIdentityState: PortIdentityState
            switch snapshotResult {
            case .success(let snapshot):
                resolvedIdentityState = identityState(for: port, using: snapshot)
            case .failure(let error):
                resolvedIdentityState = .unavailable(.lookupFailed(message: String(describing: error)))
            }
            return PortStatus(port: port, isOpen: true, identityState: resolvedIdentityState)
        }
    }

    private func identityState(
        for port: UInt16,
        using snapshot: LsofSnapshot
    ) -> PortIdentityState {
        do {
            guard let info = try lookup.info(for: port, using: snapshot) else {
                return .unavailable(.noVerifiedListener)
            }
            return .verified(info.identity)
        } catch ProcessLookupError.untrustedListeners(_, let reasons) {
            let error = ProcessLookupError.untrustedListeners(port: port, reasons: reasons)
            return .unavailable(
                .untrustedListener(message: String(describing: error))
            )
        } catch ProcessLookupError.ambiguousListeners(_, let pids) {
            return .unavailable(.ambiguousListeners(pids: pids.sorted()))
        } catch ProcessLookupError.processNameUnavailable(let pid) {
            return .unavailable(.processNameUnavailable(pid: pid))
        } catch {
            return .unavailable(.lookupFailed(message: String(describing: error)))
        }
    }
}
