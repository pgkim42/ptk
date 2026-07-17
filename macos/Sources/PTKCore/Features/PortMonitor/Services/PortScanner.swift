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
        let fd = socket(family, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let boundedTimeout = max(timeout, 0)
        var timeoutValue = timeval(
            tv_sec: Int(boundedTimeout),
            tv_usec: Int32(
                boundedTimeout.truncatingRemainder(dividingBy: 1) * 1_000_000
            )
        )
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeoutValue,
            socklen_t(MemoryLayout<timeval>.size)
        )
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeoutValue,
            socklen_t(MemoryLayout<timeval>.size)
        )

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(addressSize)) == 0
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
