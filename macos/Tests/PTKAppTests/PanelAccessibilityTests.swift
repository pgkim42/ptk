import AppKit
import SwiftUI
import Testing
@testable import PTKApp
@testable import PTKCore

@Suite struct PanelAccessibilityTests {
    @Test func openPortListUsesActualRegularAndDiagnosticRowHeights() {
        let regular = PortStatus(
            port: 3000,
            isOpen: true,
            pid: 42,
            processName: "node"
        )
        let diagnostic = PortStatus(port: 5173, isOpen: true)

        #expect(PortRowMetrics.height(for: regular) == 34)
        #expect(PortRowMetrics.height(for: diagnostic) == 44)
        #expect(OpenPortsListMetrics.height(for: [regular], maxVisibleRows: 6) == 34)
        #expect(OpenPortsListMetrics.height(for: [diagnostic], maxVisibleRows: 6) == 44)
        #expect(OpenPortsListMetrics.height(for: [regular, diagnostic], maxVisibleRows: 6) == 78)
    }

    @MainActor
    @Test func renderedDiagnosticRowIsTallerThanRenderedRegularRow() {
        let regular = PortStatus(
            port: 3000,
            isOpen: true,
            pid: 42,
            processName: "node"
        )
        let diagnostic = PortStatus(port: 5173, isOpen: true)
        let actions = (
            open: { (_: PortStatus) in },
            copy: { (_: PortStatus) in },
            details: { (_: PortStatus) in },
            kill: { (_: KillTarget) in }
        )
        let regularHost = NSHostingView(rootView: PortRowView(
            status: regular,
            onOpen: actions.open,
            onCopy: actions.copy,
            onCopyDetails: actions.details,
            onKill: actions.kill
        ).frame(width: 500))
        let diagnosticHost = NSHostingView(rootView: PortRowView(
            status: diagnostic,
            onOpen: actions.open,
            onCopy: actions.copy,
            onCopyDetails: actions.details,
            onKill: actions.kill
        ).frame(width: 500))

        #expect(regularHost.fittingSize.height >= PortRowMetrics.regularHeight)
        #expect(diagnosticHost.fittingSize.height >= PortRowMetrics.diagnosticHeight)
        #expect(diagnosticHost.fittingSize.height > regularHost.fittingSize.height)
    }

    @Test func openPortListHeightCapsRowsWithoutLosingVisibleDiagnosticHeight() {
        let regular = PortStatus(
            port: 3000,
            isOpen: true,
            pid: 42,
            processName: "node"
        )
        let diagnostic = PortStatus(port: 5173, isOpen: true)

        #expect(OpenPortsListMetrics.height(
            for: [diagnostic, regular, diagnostic],
            maxVisibleRows: 2
        ) == 78)
    }

    @Test func portControlAccessibilityIdentifiesPortAndKillTarget() throws {
        let status = PortStatus(
            port: 5173,
            isOpen: true,
            pid: 99,
            processName: "vite"
        )
        let target = try #require(status.killTarget)

        #expect(PortRowAccessibility.openLabel(for: status).contains("5173"))
        #expect(PortRowAccessibility.copyURLLabel(for: status).contains("5173"))
        #expect(PortRowAccessibility.copyDetailsLabel(for: status).contains("5173"))
        #expect(PortRowAccessibility.killLabel(for: target).contains("5173"))
        #expect(PortRowAccessibility.killLabel(for: target).contains("vite"))
        #expect(PortRowAccessibility.killLabel(for: target).contains("99"))
        #expect(PortRowAccessibility.killHint.contains("SIGTERM"))
    }

    @Test func repeatedSettingsControlsIdentifyTheirProfileOrService() {
        let profile = PortProfile(id: "frontend", title: "Frontend", expression: "3000,5173")
        let endpoint = DatabaseEndpoint(name: "PostgreSQL", port: 5432)
        let preset = PortPreset(
            id: "api",
            title: "API",
            expression: "8000-8009",
            detail: "Local backend"
        )

        #expect(SettingsAccessibility.profileApplyLabel(profile) == "프로필 Frontend 적용")
        #expect(SettingsAccessibility.profileDeleteLabel(profile) == "프로필 Frontend 삭제")
        #expect(SettingsAccessibility.serviceDeleteLabel(endpoint).contains("PostgreSQL"))
        #expect(SettingsAccessibility.serviceDeleteLabel(endpoint).contains("5432"))
        #expect(SettingsAccessibility.presetApplyLabel(preset) == "포트 프리셋 API 적용")
        #expect(!SettingsAccessibility.refreshIntervalPickerLabel.isEmpty)
        #expect(!SettingsAccessibility.themePickerLabel.isEmpty)
        #expect(!SettingsAccessibility.refreshIntervalPickerHint.isEmpty)
        #expect(!SettingsAccessibility.themePickerHint.isEmpty)
    }

    @Test func dockerCopyControlIdentifiesContainerAndURL() {
        let row = DockerContainerPortRow(
            id: "api",
            name: "api",
            detail: "127.0.0.1:8080 -> 8080"
        )
        let url = "http://localhost:8080"

        #expect(ServiceRowAccessibility.copyLabel(for: row, url: url).contains("api"))
        #expect(ServiceRowAccessibility.copyLabel(for: row, url: url).contains(url))
        #expect(ServiceRowAccessibility.copyHint(for: url).contains(url))
    }
}
