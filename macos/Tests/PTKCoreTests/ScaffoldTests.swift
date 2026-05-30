import Testing
@testable import PTKCore

@Test func exposesAppName() {
    #expect(PTKCore.appName == "PTK")
}
