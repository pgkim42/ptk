import Testing
@testable import PTKCore

@Suite struct MenuModelTests {
    @Test func emptyOpenPortsRenderEmptyState() {
        let model = MenuModel(statuses: [PortStatus(port: 3000, isOpen: false)])
        #expect(model.title == "PTK 0")
        #expect(model.isEmpty)
        #expect(model.refreshIntervals == [.oneSecond, .threeSeconds, .fiveSeconds, .tenSeconds])
    }

    @Test func openCountIncludesOnlyOpenWatchedPorts() {
        let model = MenuModel(statuses: [
            PortStatus(port: 3000, isOpen: true, pid: 100, processName: "node"),
            PortStatus(port: 3001, isOpen: false),
            PortStatus(port: 5173, isOpen: true, pid: 200, processName: "vite")
        ])

        #expect(model.title == "PTK 2")
        #expect(model.rows.map(\.port) == [3000, 5173])
    }

    @Test func rowsIncludePortPidAndProcessName() {
        let row = MenuModel(statuses: [
            PortStatus(port: 5173, isOpen: true, pid: 333, processName: "vite")
        ]).rows[0]

        #expect(row.displayText == "Port 5173 · PID 333 · vite")
        #expect(row.canRequestKill)
    }

    @Test func rowsWithoutSafeKillTargetCannotRequestKill() {
        let rows = MenuModel(statuses: [
            PortStatus(port: 3000, isOpen: true),
            PortStatus(port: 3001, isOpen: true, pid: 0, processName: "node"),
            PortStatus(port: 3002, isOpen: true, pid: 222)
        ]).rows

        #expect(rows.allSatisfy { !$0.canRequestKill })
    }

    @Test func errorStateDoesNotHideRows() {
        let model = MenuModel(
            statuses: [PortStatus(port: 3000, isOpen: true, pid: 111, processName: "node")],
            errorMessage: "lookup failed"
        )

        #expect(model.errorMessage == "lookup failed")
        #expect(model.rows.count == 1)
    }
}
