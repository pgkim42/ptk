public struct LsofParser: Sendable {
    public init() {}

    public func parseListeningPIDMap(_ stdout: String) -> [UInt16: Int] {
        var output: [UInt16: Int] = [:]

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            let text = String(line)
            guard text.contains("(LISTEN)") else { continue }

            let columns = text.split { $0.isWhitespace }.map(String.init)
            guard columns.count >= 2, let pid = Int(columns[1]), pid > 0 else { continue }
            guard let name = tcpName(in: text), let port = parsePort(fromTCPName: name) else { continue }
            output[port, default: pid] = output[port] ?? pid
        }

        return output
    }

    private func tcpName(in line: String) -> String? {
        guard let range = line.range(of: " TCP ") else { return nil }
        let rest = line[range.upperBound...]
        return rest.split { $0.isWhitespace }.first.map(String.init)
    }

    public func parsePort(fromTCPName name: String) -> UInt16? {
        guard !name.contains("->") else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(of: ":") else { return nil }
        let portText = String(trimmed[trimmed.index(after: separator)...])
        guard let value = Int(portText), (1...65_535).contains(value) else { return nil }
        return UInt16(value)
    }
}
