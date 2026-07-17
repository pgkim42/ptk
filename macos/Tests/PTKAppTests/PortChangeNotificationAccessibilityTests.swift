import Testing
@testable import PTKApp

@Suite struct PortChangeNotificationAccessibilityTests {
    @Test func settingsSheetConsumesNotificationAccessibilityValuesAtItsControls() {
        let accessibility = SettingsSheetNotificationAccessibility()

        #expect(accessibility.toggleLabel == "포트 변경 알림")
        #expect(accessibility.toggleHint == "선택한 포트가 열리거나 닫힐 때 알림을 받도록 켜거나 끕니다.")
        #expect(accessibility.toggleIdentifier == "settings.portChangeNotification.toggle")

        #expect(accessibility.expressionLabel == "알림 포트")
        #expect(accessibility.expressionHint == "알림을 받을 포트를 쉼표 또는 범위로 입력합니다.")
        #expect(accessibility.expressionIdentifier == "settings.portChangeNotification.portsExpression")

        #expect(accessibility.deniedStatusLabel == "알림 권한이 macOS에서 차단됨")
        #expect(accessibility.deniedStatusIdentifier == "settings.portChangeNotification.permissionDenied")
        #expect(accessibility.systemSettingsButtonLabel == "시스템 설정 열기")
        #expect(accessibility.systemSettingsButtonHint == "macOS 알림 설정에서 PTK 알림 권한을 변경합니다.")
        #expect(accessibility.systemSettingsButtonIdentifier == "settings.portChangeNotification.openSystemSettings")

        #expect(accessibility.validationErrorLabel("잘못된 포트 표현식") == "알림 포트 입력 오류: 잘못된 포트 표현식")
        #expect(accessibility.validationErrorIdentifier == "settings.portChangeNotification.validationError")
        #expect(accessibility.permissionErrorLabel("설정을 열 수 없습니다.") == "알림 설정 오류: 설정을 열 수 없습니다.")
        #expect(accessibility.permissionErrorIdentifier == "settings.portChangeNotification.permissionError")
    }

    @Test(arguments: [
        (false, PortChangeNotificationPermissionStatus.unknown, nil, (false, false, false, false)),
        (false, .denied, "잘못된 포트 표현식", (false, false, false, true)),
        (true, .notDetermined, nil, (true, false, false, false)),
        (true, .unknown, "잘못된 포트 표현식", (true, false, false, true)),
        (true, .denied, nil, (true, true, true, false)),
        (true, .denied, "잘못된 포트 표현식", (true, true, true, true)),
        (true, .authorized, nil, (true, false, false, false)),
        (true, .authorized, "잘못된 포트 표현식", (true, false, false, true))
    ])
    func notificationControlVisibilityCoversPermissionAndValidationRiskStates(
        isEnabled: Bool,
        permissionStatus: PortChangeNotificationPermissionStatus,
        validationError: String?,
        expected: (Bool, Bool, Bool, Bool)
    ) {
        let controls = SettingsAccessibility.portChangeNotificationControls(
            isEnabled: isEnabled,
            permissionStatus: permissionStatus,
            validationError: validationError
        )

        #expect(
            (
                controls.showsPortExpression,
                controls.showsDeniedStatus,
                controls.showsSystemSettingsButton,
                controls.showsValidationError
            ) == expected
        )
    }
}
