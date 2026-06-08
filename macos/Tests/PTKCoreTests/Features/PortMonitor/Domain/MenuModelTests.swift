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

    @Test func rowsExposeWhyKillCannotBeRequested() {
        let rows = MenuModel(statuses: [
            PortStatus(port: 3000, isOpen: true),
            PortStatus(port: 3001, isOpen: true, pid: 222),
            PortStatus(
                port: 3002,
                isOpen: true,
                message: "ambiguous process lookup: port 3002 has PIDs 1, 2"
            ),
            PortStatus(port: 3003, isOpen: true, pid: 333, processName: "node"),
            PortStatus(port: 3004, isOpen: false)
        ]).rows

        #expect(rows[0].killUnavailableReason == "process lookup unavailable: PID not found")
        #expect(rows[1].killUnavailableReason == "process lookup unavailable: process name not found")
        #expect(rows[2].killUnavailableReason == "ambiguous process lookup: port 3002 has PIDs 1, 2")
        #expect(rows[3].killUnavailableReason == nil)
        #expect(rows.map(\.port) == [3000, 3001, 3002, 3003])
    }

    @Test func portChangesDetectOpenClosedAndProcessUpdates() {
        let previous = [
            PortStatus(port: 3000, isOpen: false),
            PortStatus(port: 3001, isOpen: true, pid: 10, processName: "node"),
            PortStatus(port: 3002, isOpen: true, pid: 20, processName: "vite")
        ]
        let current = [
            PortStatus(port: 3000, isOpen: true, pid: 30, processName: "rails"),
            PortStatus(port: 3001, isOpen: false),
            PortStatus(port: 3002, isOpen: true, pid: 21, processName: "vite")
        ]

        let changes = PortChange.detect(previous: previous, current: current)

        #expect(changes.map(\.kind) == [.opened, .closed, .changed])
        #expect(changes.map(\.displayText) == [
            "3000 · 열림 · rails · PID 30",
            "3001 · 닫힘",
            "3002 · 변경 · vite · PID 21"
        ])
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
