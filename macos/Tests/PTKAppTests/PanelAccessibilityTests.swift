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

    @Test func panelLabelsUseConsistentKoreanTerms() {
        let port = PortStatus(port: 3000, isOpen: true, pid: 42, processName: "node")
        let service = ServiceStatus(name: "PostgreSQL", detail: "5432", state: .running)
        let dockerRow = DockerContainerPortRow(id: "api", name: "api", detail: "3000 -> 3000")

        #expect(PortRowAccessibility.openLabel(for: port) == "포트 3000 로컬 주소 열기")
        #expect(PortRowAccessibility.copyURLLabel(for: port) == "포트 3000 로컬 주소 복사")
        #expect(ServiceRowAccessibility.statusLabel(for: service) == "PostgreSQL 서비스, 5432, 상태 실행 중")
        #expect(
            ServiceRowAccessibility.copyLabel(for: dockerRow, url: "http://localhost:3000")
                == "Docker 서비스 api 주소 복사, http://localhost:3000"
        )
        #expect(ServiceGroup.builtIn.label == "기본 서비스")
        #expect(ServiceGroup.custom.label == "사용자 서비스")
        #expect(ServiceState.stopped.label == "중지됨")
        #expect(ServiceState.unavailable.label == "확인 불가")
    }
}
