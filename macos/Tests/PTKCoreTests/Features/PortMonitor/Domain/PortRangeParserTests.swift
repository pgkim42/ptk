import Testing
@testable import PTKCore

@Suite struct PortRangeParserTests {
    let parser = PortRangeParser()

    @Test func parsesMixedInputSortedUnique() throws {
        #expect(try parser.parse("8080, 3000-3002 8080") == [3000, 3001, 3002, 8080])
    }

    @Test func rejectsInvalidTokens() {
        #expect(throws: PortRangeParserError.invalidToken("nope")) {
            try parser.parse("8080,nope,3000-2x")
        }
    }

    @Test func rejectsZeroReversedAndOutOfRange() {
        #expect(throws: PortRangeParserError.portOutOfRange("0")) {
            try parser.parse("0")
        }
        #expect(throws: PortRangeParserError.invalidRange("3000-2")) {
            try parser.parse("3000-2")
        }
        #expect(throws: PortRangeParserError.portOutOfRange("70000")) {
            try parser.parse("70000")
        }
    }

    @Test func enforcesMaxCount() {
        let parser = PortRangeParser(maxPortCount: 3)
        #expect(throws: PortRangeParserError.maxPortCountExceeded(3)) {
            try parser.parse("1-4")
        }
    }

}
