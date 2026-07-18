import Testing
@testable import PTKCore

@Suite struct LsofParserTests {
    private let header = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n"

    @Test func classifiesWildcardAndExactLoopbackListenersByFamily() {
        let sample = header + """
        node 101 user 20u IPv4 0x1 0t0 TCP *:4101 (LISTEN)
        node 102 user 20u IPv4 0x2 0t0 TCP 0.0.0.0:4102 (LISTEN)
        node 103 user 20u IPv4 0x3 0t0 TCP 127.0.0.1:4103 (LISTEN)
        node 104 user 20u IPv6 0x4 0t0 TCP *:4201 (LISTEN)
        node 105 user 20u IPv6 0x5 0t0 TCP [::]:4202 (LISTEN)
        node 106 user 20u IPv6 0x6 0t0 TCP :::4203 (LISTEN)
        node 107 user 20u IPv6 0x7 0t0 TCP [::1]:4204 (LISTEN)
        """

        let snapshot = LsofParser().parse(sample)

        #expect(snapshot.records.count == 7)
        #expect(record(for: 4101, in: snapshot)?.family == .ipv4)
        #expect(record(for: 4101, in: snapshot)?.address == "*")
        #expect(record(for: 4102, in: snapshot)?.trust == .verifiedLoopbackCompatible)
        #expect(record(for: 4103, in: snapshot)?.trust == .verifiedLoopbackCompatible)
        #expect(record(for: 4201, in: snapshot)?.family == .ipv6)
        #expect(record(for: 4202, in: snapshot)?.address == "[::]")
        #expect(record(for: 4203, in: snapshot)?.address == "::")
        #expect(record(for: 4204, in: snapshot)?.address == "[::1]")
        #expect(snapshot.records.allSatisfy { $0.trust == .verifiedLoopbackCompatible })
    }

    @Test func collapsesSamePIDAcrossFamilies() {
        let sample = header + """
        node 200 user 20u IPv4 0x1 0t0 TCP *:5000 (LISTEN)
        node 200 user 21u IPv6 0x2 0t0 TCP *:5000 (LISTEN)
        """

        let resolution = LsofParser().parse(sample).resolution(for: 5000)

        #expect(resolution == .verified(pid: 200))
    }

    @Test func returnsSortedDistinctPIDsForAmbiguousListeners() {
        let sample = header + """
        node 303 user 20u IPv6 0x1 0t0 TCP [::1]:5001 (LISTEN)
        node 101 user 21u IPv4 0x2 0t0 TCP 127.0.0.1:5001 (LISTEN)
        node 303 user 22u IPv4 0x3 0t0 TCP *:5001 (LISTEN)
        """

        let resolution = LsofParser().parse(sample).resolution(for: 5001)

        #expect(resolution == .ambiguous(pids: [101, 303]))
    }

    @Test func remoteAndEstablishedRowsDoNotPoisonExactListener() {
        let sample = header + """
        node 400 user 20u IPv4 0x1 0t0 TCP 127.0.0.1:5100 (LISTEN)
        node 401 user 21u IPv4 0x2 0t0 TCP 192.168.1.20:5100 (LISTEN)
        node 402 user 22u IPv6 0x3 0t0 TCP [2001:db8::1]:5100 (LISTEN)
        curl 403 user 23u IPv4 0x4 0t0 TCP 127.0.0.1:5100->127.0.0.1:80 (ESTABLISHED)
        """

        let snapshot = LsofParser().parse(sample)

        #expect(record(pid: 401, in: snapshot)?.trust == .untrusted(reason: .remoteOrInterfaceOnly))
        #expect(record(pid: 402, in: snapshot)?.trust == .untrusted(reason: .remoteOrInterfaceOnly))
        #expect(record(pid: 403, in: snapshot)?.trust == .untrusted(reason: .established))
        #expect(snapshot.resolution(for: 5100) == .verified(pid: 400))
    }

    @Test func familyAddressConflictsPoisonVerifiedEvidence() {
        let sample = header + """
        node 500 user 20u IPv4 0x1 0t0 TCP 127.0.0.1:5200 (LISTEN)
        node 501 user 21u IPv4 0x2 0t0 TCP [::1]:5200 (LISTEN)
        node 502 user 22u IPv6 0x3 0t0 TCP 127.0.0.1:5201 (LISTEN)
        """

        let snapshot = LsofParser().parse(sample)

        #expect(record(pid: 501, in: snapshot)?.trust == .untrusted(reason: .familyAddressConflict))
        #expect(record(pid: 502, in: snapshot)?.trust == .untrusted(reason: .familyAddressConflict))
        #expect(snapshot.resolution(for: 5200) == .untrusted(reasons: [.familyAddressConflict]))
        #expect(snapshot.resolution(for: 5201) == .untrusted(reasons: [.familyAddressConflict]))
    }

    @Test func unknownFamilyAndAddressProduceSortedUntrustedReasons() {
        let sample = header + """
        node 600 user 20u mystery 0x1 0t0 TCP *:5300 (LISTEN)
        node 601 user 21u IPv4 0x2 0t0 TCP localhost:5300 (LISTEN)
        node 602 user 22u mystery 0x3 0t0 TCP mystery:5300 (LISTEN)
        """

        let snapshot = LsofParser().parse(sample)

        #expect(record(pid: 600, in: snapshot)?.family == .unknown)
        #expect(record(pid: 600, in: snapshot)?.trust == .untrusted(reason: .unknownFamily))
        #expect(record(pid: 601, in: snapshot)?.trust == .untrusted(reason: .unknownAddress))
        #expect(
            snapshot.resolution(for: 5300)
                == .untrusted(reasons: [.unknownFamily, .unknownAddress])
        )
    }

    @Test func retainsMalformedPIDBracketsAndPortAsConservativeEvidence() {
        let sample = header + """
        node nope user 20u IPv4 0x1 0t0 TCP *:5400 (LISTEN)
        node 701 user 21u IPv6 0x2 0t0 TCP [::1:5401 (LISTEN)
        node 702 user 22u IPv4 0x3 0t0 TCP *:notaport (LISTEN)
        node 703 user 23u IPv4 0x4 0t0 TCP 127.0.0.1:5499 (LISTEN)
        """

        let snapshot = LsofParser().parse(sample)
        let malformedPID = record(for: 5400, in: snapshot)
        let malformedBrackets = record(for: 5401, in: snapshot)
        let malformedPort = snapshot.records.first { $0.pid == 702 }

        #expect(malformedPID?.pid == nil)
        #expect(malformedPID?.trust == .untrusted(reason: .malformed))
        #expect(malformedBrackets?.address == "[::1")
        #expect(malformedBrackets?.trust == .untrusted(reason: .malformed))
        #expect(malformedPort?.port == nil)
        #expect(malformedPort?.trust == .untrusted(reason: .malformed))
        #expect(snapshot.resolution(for: 5400) == .untrusted(reasons: [.malformed]))
        #expect(snapshot.resolution(for: 5401) == .untrusted(reasons: [.malformed]))
        #expect(snapshot.resolution(for: 5499) == .untrusted(reasons: [.malformed]))
        #expect(snapshot.resolution(for: 65000) == .untrusted(reasons: [.malformed]))
    }

    @Test func parsesSupportedPortsWithoutTreatingConnectionsAsListeners() {
        let parser = LsofParser()

        #expect(parser.parsePort(fromTCPName: "*:3000") == 3000)
        #expect(parser.parsePort(fromTCPName: "127.0.0.1:5173") == 5173)
        #expect(parser.parsePort(fromTCPName: "[::1]:4200") == 4200)
        #expect(parser.parsePort(fromTCPName: ":::4201") == 4201)
        #expect(parser.parsePort(fromTCPName: "127.0.0.1:61000->127.0.0.1:3000") == nil)
        #expect(parser.parsePort(fromTCPName: "invalid") == nil)
    }

    private func record(for port: UInt16, in snapshot: LsofSnapshot) -> LsofListenerRecord? {
        snapshot.records.first { $0.port == port }
    }

    private func record(pid: Int, in snapshot: LsofSnapshot) -> LsofListenerRecord? {
        snapshot.records.first { $0.pid == pid }
    }
}
