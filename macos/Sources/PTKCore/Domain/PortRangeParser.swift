public enum PortRangeParserError: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case invalidToken(String)
    case invalidRange(String)
    case portOutOfRange(String)
    case maxPortCountExceeded(Int)

    public var description: String {
        switch self {
        case .emptyInput:
            return "port expression is empty"
        case .invalidToken(let token):
            return "invalid port token: \(token)"
        case .invalidRange(let token):
            return "invalid port range: \(token)"
        case .portOutOfRange(let token):
            return "port out of range: \(token)"
        case .maxPortCountExceeded(let max):
            return "too many ports; maximum is \(max)"
        }
    }
}

public struct PortRangeParser: Sendable {
    public let maxPortCount: Int

    public init(maxPortCount: Int = AppDefaults.maxPortCount) {
        self.maxPortCount = maxPortCount
    }

    public func parse(_ input: String) throws -> [UInt16] {
        let tokens = input
            .split { char in char == "," || char.isWhitespace }
            .map(String.init)

        guard !tokens.isEmpty else { throw PortRangeParserError.emptyInput }

        var ports = Set<UInt16>()
        for token in tokens {
            if token.contains("-") {
                try insertRange(token, into: &ports)
            } else {
                try insertPort(token, into: &ports)
            }
            if ports.count > maxPortCount {
                throw PortRangeParserError.maxPortCountExceeded(maxPortCount)
            }
        }

        return ports.sorted()
    }

    private func insertPort(_ token: String, into ports: inout Set<UInt16>) throws {
        guard let value = Int(token) else {
            throw PortRangeParserError.invalidToken(token)
        }
        guard (1...65_535).contains(value) else {
            throw PortRangeParserError.portOutOfRange(token)
        }
        ports.insert(UInt16(value))
    }

    private func insertRange(_ token: String, into ports: inout Set<UInt16>) throws {
        let pieces = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 2,
              let start = Int(pieces[0]),
              let end = Int(pieces[1]) else {
            throw PortRangeParserError.invalidRange(token)
        }
        guard (1...65_535).contains(start), (1...65_535).contains(end) else {
            throw PortRangeParserError.portOutOfRange(token)
        }
        guard start <= end else {
            throw PortRangeParserError.invalidRange(token)
        }

        for port in start...end {
            ports.insert(UInt16(port))
            if ports.count > maxPortCount {
                throw PortRangeParserError.maxPortCountExceeded(maxPortCount)
            }
        }
    }
}
