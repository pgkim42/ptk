import Darwin
import Foundation

public protocol SocketConnecting {
    func isListening(host: String, port: UInt16, timeout: TimeInterval) -> Bool
}

public struct TCPPortConnector: SocketConnecting {
    public init() {}

    public func isListening(host: String, port: UInt16, timeout: TimeInterval = 0.2) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

public struct PortScanner {
    private let connector: SocketConnecting
    private let lookup: ProcessLookup
    private let timeout: TimeInterval

    public init(
        connector: SocketConnecting = TCPPortConnector(),
        lookup: ProcessLookup = ProcessLookup(),
        timeout: TimeInterval = 0.2
    ) {
        self.connector = connector
        self.lookup = lookup
        self.timeout = max(timeout, 0.05)
    }

    public func scan(ports: [UInt16], host: String = "127.0.0.1") -> [PortStatus] {
        let lookupResult = Result { try lookup.listeningPortPIDMap() }

        return ports.map { port in
            guard connector.isListening(host: host, port: port, timeout: timeout) else {
                return PortStatus(port: port, isOpen: false)
            }

            switch lookupResult {
            case .success(let pidMap):
                guard let pid = pidMap[port] else {
                    return PortStatus(port: port, isOpen: true)
                }
                return PortStatus(
                    port: port,
                    isOpen: true,
                    pid: pid,
                    processName: lookup.processName(pid: pid)
                )
            case .failure(let error):
                return PortStatus(port: port, isOpen: true, message: "process lookup failed: \(error)")
            }
        }
    }
}
