import Testing
@testable import PTKCore

@Suite struct LsofParserTests {
    @Test func parsesListeningPortsAndKeepsFirstPID() {
        let sample = """
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node      111 pgkim  20u  IPv4 0xabcd      0t0  TCP *:3000 (LISTEN)
node      222 pgkim  21u  IPv6 0xbcde      0t0  TCP *:3000 (LISTEN)
vite      333 pgkim  15u  IPv4 0xcdef      0t0  TCP 127.0.0.1:5173 (LISTEN)
postgres  444 pgkim   7u  IPv6 0xdef0      0t0  TCP [::1]:4200 (LISTEN)
curl      555 pgkim   8u  IPv4 0xef01      0t0  TCP 127.0.0.1:61000->127.0.0.1:3000 (ESTABLISHED)
bad       nope pgkim  8u  IPv4 0xef01      0t0  TCP *:8080 (LISTEN)
"""

        let map = LsofParser().parseListeningPIDMap(sample)
        #expect(map[3000] == 111)
        #expect(map[5173] == 333)
        #expect(map[4200] == 444)
        #expect(map[61000] == nil)
        #expect(map[8080] == nil)
    }

    @Test func parsesSupportedAddressForms() {
        let parser = LsofParser()
        #expect(parser.parsePort(fromTCPName: "*:3000") == 3000)
        #expect(parser.parsePort(fromTCPName: "127.0.0.1:5173") == 5173)
        #expect(parser.parsePort(fromTCPName: "[::1]:4200") == 4200)
        #expect(parser.parsePort(fromTCPName: "127.0.0.1:61000->127.0.0.1:3000") == nil)
        #expect(parser.parsePort(fromTCPName: "invalid") == nil)
    }
}
