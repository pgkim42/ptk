import AppKit
import SwiftUI
import Testing
@testable import PTKApp
@testable import PTKCore

@Suite struct PanelAccessibilityTests {
    @MainActor
    @Test func diagnosticRowRendersTallerThanRegularRow() {
        let regular = PortStatus(port: 3000, isOpen: true, pid: 42, processName: "node")
        let diagnostic = PortStatus(port: 5173, isOpen: true)
        let regularHost = NSHostingView(rootView: PortRowView(
            status: regular,
            onOpen: { _ in },
            onCopy: { _ in },
            onCopyDetails: { _ in },
            onKill: { _ in }
        ).frame(width: 500))
        let diagnosticHost = NSHostingView(rootView: PortRowView(
            status: diagnostic,
            onOpen: { _ in },
            onCopy: { _ in },
            onCopyDetails: { _ in },
            onKill: { _ in }
        ).frame(width: 500))

        #expect(regularHost.fittingSize.height >= PortRowMetrics.regularHeight)
        #expect(diagnosticHost.fittingSize.height >= PortRowMetrics.diagnosticHeight)
        #expect(diagnosticHost.fittingSize.height > regularHost.fittingSize.height)
    }
}
