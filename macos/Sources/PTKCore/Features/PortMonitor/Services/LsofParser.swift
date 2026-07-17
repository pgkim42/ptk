import Foundation
import Darwin

public enum LsofAddressFamily: Sendable, Hashable {
    case ipv4
    case ipv6
    case unknown
}

public enum LsofUntrustedReason: Sendable, Hashable {
    case remoteOrInterfaceOnly
    case established
    case unknownFamily
    case unknownAddress
    case malformed
    case familyAddressConflict
}

public enum LsofListenerTrust: Sendable, Hashable {
    case verifiedLoopbackCompatible
    case untrusted(reason: LsofUntrustedReason)
}

public struct LsofListenerRecord: Sendable, Hashable {
    public let port: UInt16?
    public let pid: Int?
    public let family: LsofAddressFamily
    public let address: String?
    public let trust: LsofListenerTrust

    public init(
        port: UInt16?,
        pid: Int?,
        family: LsofAddressFamily,
        address: String?,
        trust: LsofListenerTrust
    ) {
        self.port = port
        self.pid = pid
        self.family = family
        self.address = address
        self.trust = trust
    }
}

public enum LocalListenerResolution: Sendable, Equatable {
    case absent
    case verified(pid: Int)
    case ambiguous(pids: [Int])
    case untrusted(reasons: [LsofUntrustedReason])
}

public struct LsofSnapshot: Sendable, Equatable {
    public let records: [LsofListenerRecord]

    public init(records: [LsofListenerRecord]) {
        self.records = records
    }

    public func resolution(for port: UInt16) -> LocalListenerResolution {
        var verifiedPIDs = Set<Int>()
        var untrustedReasons = Set<LsofUntrustedReason>()
        var poisonReasons = Set<LsofUntrustedReason>()

        for record in records {
            let isRequestedPort = record.port == port
            let isGlobalMalformedRecord =
                record.port == nil && record.trust == .untrusted(reason: .malformed)
            guard isRequestedPort || isGlobalMalformedRecord else { continue }

            switch record.trust {
            case .verifiedLoopbackCompatible:
                guard isRequestedPort, let pid = record.pid, pid > 0 else {
                    untrustedReasons.insert(.malformed)
                    poisonReasons.insert(.malformed)
                    continue
                }
                verifiedPIDs.insert(pid)
            case let .untrusted(reason):
                untrustedReasons.insert(reason)
                if reason.poisonsIdentityResolution {
                    poisonReasons.insert(reason)
                }
            }
        }

        if !poisonReasons.isEmpty {
            return .untrusted(reasons: poisonReasons.sortedByResolutionOrder)
        }

        let pids = verifiedPIDs.sorted()
        switch pids.count {
        case 0 where !untrustedReasons.isEmpty:
            return .untrusted(reasons: untrustedReasons.sortedByResolutionOrder)
        case 0:
            return .absent
        case 1:
            return .verified(pid: pids[0])
        default:
            return .ambiguous(pids: pids)
        }
    }
}

public struct LsofParser: Sendable {
    public init() {}

    public func parse(_ stdout: String) -> LsofSnapshot {
        let records = stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseTCPRecord(String($0)) }
        return LsofSnapshot(records: records)
    }

    public func parseListeningPIDMap(_ stdout: String) -> [UInt16: Set<Int>] {
        let snapshot = parse(stdout)
        var output: [UInt16: Set<Int>] = [:]

        for port in Set(snapshot.records.compactMap(\.port)).sorted() {
            switch snapshot.resolution(for: port) {
            case let .verified(pid):
                output[port] = [pid]
            case let .ambiguous(pids):
                output[port] = Set(pids)
            case .absent, .untrusted:
                break
            }
        }

        return output
    }

    public func parsePort(fromTCPName name: String) -> UInt16? {
        guard !name.contains("->") else { return nil }
        return parseEndpoint(name).port
    }

    private func parseTCPRecord(_ line: String) -> LsofListenerRecord? {
        let columns = line.split { $0.isWhitespace }.map(String.init)
        guard let tcpIndex = columns.firstIndex(of: "TCP") else { return nil }

        let pid = columns.count > 1 ? positivePID(columns[1]) : nil
        let family = columns.count > 4 ? parseFamily(columns[4]) : .unknown
        let stateColumns = columns.suffix(from: columns.index(after: tcpIndex))
        let isEstablished = stateColumns.contains { $0 == "(ESTABLISHED)" }
        let isListening = stateColumns.contains { $0 == "(LISTEN)" }
        let name = columns.indices.contains(tcpIndex + 1)
            && !columns[tcpIndex + 1].hasPrefix("(")
            ? columns[tcpIndex + 1]
            : nil
        let sourceName = name?.split(separator: "->", maxSplits: 1).first.map(String.init)
        let endpoint = sourceName.map(parseEndpoint)

        let trust: LsofListenerTrust
        if name?.contains("->") == true || isEstablished {
            trust = .untrusted(reason: .established)
        } else if !isListening || pid == nil || endpoint == nil
            || endpoint?.port == nil || endpoint?.isMalformed == true {
            trust = .untrusted(reason: .malformed)
        } else {
            trust = classify(family: family, address: endpoint?.address)
        }

        return LsofListenerRecord(
            port: endpoint?.port,
            pid: pid,
            family: family,
            address: endpoint?.address,
            trust: trust
        )
    }

    private func positivePID(_ text: String) -> Int? {
        guard let pid = Int(text), pid > 0 else { return nil }
        return pid
    }

    private func parseFamily(_ text: String) -> LsofAddressFamily {
        switch text {
        case "IPv4":
            return .ipv4
        case "IPv6":
            return .ipv6
        default:
            return .unknown
        }
    }

    private func classify(
        family: LsofAddressFamily,
        address: String?
    ) -> LsofListenerTrust {
        guard let address else {
            return .untrusted(reason: .unknownAddress)
        }

        let kind = addressKind(address)
        switch family {
        case .ipv4:
            switch kind {
            case .wildcard:
                return .verifiedLoopbackCompatible
            case let .ipv4(value):
                return value == "0.0.0.0" || value == "127.0.0.1"
                    ? .verifiedLoopbackCompatible
                    : .untrusted(reason: .remoteOrInterfaceOnly)
            case .ipv6:
                return .untrusted(reason: .familyAddressConflict)
            case .unknown:
                return .untrusted(reason: .unknownAddress)
            }
        case .ipv6:
            switch kind {
            case .wildcard:
                return .verifiedLoopbackCompatible
            case let .ipv6(value):
                return value == "::" || value == "::1"
                    ? .verifiedLoopbackCompatible
                    : .untrusted(reason: .remoteOrInterfaceOnly)
            case .ipv4:
                return .untrusted(reason: .familyAddressConflict)
            case .unknown:
                return .untrusted(reason: .unknownAddress)
            }
        case .unknown:
            return .untrusted(reason: .unknownFamily)
        }
    }

    private func addressKind(_ address: String) -> AddressKind {
        if address == "*" {
            return .wildcard
        }

        let unwrapped: String
        if address.hasPrefix("["), address.hasSuffix("]") {
            unwrapped = String(address.dropFirst().dropLast())
        } else {
            unwrapped = address
        }

        if isIPv4Address(unwrapped) {
            return .ipv4(unwrapped)
        }
        if isIPv6Address(unwrapped) {
            return .ipv6(unwrapped)
        }
        return .unknown
    }

    private func isIPv4Address(_ address: String) -> Bool {
        var storage = in_addr()
        return address.withCString { inet_pton(AF_INET, $0, &storage) == 1 }
    }

    private func isIPv6Address(_ address: String) -> Bool {
        var storage = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &storage) == 1 }
    }

    private func parseEndpoint(_ text: String) -> ParsedEndpoint {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedEndpoint(address: nil, port: nil, isMalformed: true)
        }

        if trimmed.hasPrefix("[") {
            guard let closingBracket = trimmed.firstIndex(of: "]") else {
                return recoverMalformedEndpoint(trimmed)
            }
            let address = String(trimmed[...closingBracket])
            let remainder = trimmed[trimmed.index(after: closingBracket)...]
            guard remainder.first == ":" else {
                return ParsedEndpoint(address: address, port: nil, isMalformed: true)
            }
            let portText = String(remainder.dropFirst())
            return ParsedEndpoint(
                address: address,
                port: validPort(portText),
                isMalformed: validPort(portText) == nil
            )
        }

        guard let separator = trimmed.lastIndex(of: ":") else {
            return ParsedEndpoint(address: trimmed, port: nil, isMalformed: true)
        }

        let address = String(trimmed[..<separator])
        let portText = String(trimmed[trimmed.index(after: separator)...])
        return ParsedEndpoint(
            address: address.isEmpty ? nil : address,
            port: validPort(portText),
            isMalformed: address.isEmpty || validPort(portText) == nil
        )
    }

    private func recoverMalformedEndpoint(_ text: String) -> ParsedEndpoint {
        guard let separator = text.lastIndex(of: ":") else {
            return ParsedEndpoint(address: text, port: nil, isMalformed: true)
        }
        let address = String(text[..<separator])
        let portText = String(text[text.index(after: separator)...])
        return ParsedEndpoint(
            address: address.isEmpty ? nil : address,
            port: validPort(portText),
            isMalformed: true
        )
    }

    private func validPort(_ text: String) -> UInt16? {
        guard let value = Int(text), (1...65_535).contains(value) else { return nil }
        return UInt16(value)
    }
}

private struct ParsedEndpoint {
    let address: String?
    let port: UInt16?
    let isMalformed: Bool
}

private enum AddressKind {
    case wildcard
    case ipv4(String)
    case ipv6(String)
    case unknown
}

private extension LsofUntrustedReason {
    var poisonsIdentityResolution: Bool {
        switch self {
        case .remoteOrInterfaceOnly, .established:
            return false
        case .unknownFamily, .unknownAddress, .malformed, .familyAddressConflict:
            return true
        }
    }

    var resolutionOrder: Int {
        switch self {
        case .remoteOrInterfaceOnly:
            return 0
        case .established:
            return 1
        case .unknownFamily:
            return 2
        case .unknownAddress:
            return 3
        case .malformed:
            return 4
        case .familyAddressConflict:
            return 5
        }
    }
}

private extension Set where Element == LsofUntrustedReason {
    var sortedByResolutionOrder: [LsofUntrustedReason] {
        sorted { $0.resolutionOrder < $1.resolutionOrder }
    }
}
