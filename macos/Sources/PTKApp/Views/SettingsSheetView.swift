import SwiftUI
import PTKCore

@MainActor
struct SettingsSheetActions {
    let viewModel: PortMonitorViewModel
    let onDismiss: () -> Void

    func cancel() {
        onDismiss()
    }

    func save(_ draft: SettingsDraft) throws {
        try viewModel.saveSettingsDraft(draft)
        onDismiss()
    }
}

struct SettingsSheetNotificationAccessibility {
    let toggleLabel = SettingsAccessibility.portChangeNotificationToggleLabel
    let toggleHint = SettingsAccessibility.portChangeNotificationToggleHint
    let toggleIdentifier = SettingsAccessibility.portChangeNotificationToggleIdentifier
    let expressionLabel = SettingsAccessibility.notificationPortExpressionLabel
    let expressionHint = SettingsAccessibility.notificationPortExpressionHint
    let expressionIdentifier = SettingsAccessibility.notificationPortExpressionIdentifier
    let deniedStatusLabel = SettingsAccessibility.notificationDeniedStatusLabel
    let deniedStatusIdentifier = SettingsAccessibility.notificationDeniedStatusIdentifier
    let systemSettingsButtonLabel = SettingsAccessibility.notificationSystemSettingsButtonLabel
    let systemSettingsButtonHint = SettingsAccessibility.notificationSystemSettingsButtonHint
    let systemSettingsButtonIdentifier = SettingsAccessibility.notificationSystemSettingsButtonIdentifier
    let validationErrorIdentifier = SettingsAccessibility.notificationValidationErrorIdentifier
    let permissionErrorIdentifier = SettingsAccessibility.notificationPermissionErrorIdentifier

    func validationErrorLabel(_ error: String) -> String {
        SettingsAccessibility.notificationValidationErrorLabel(error)
    }

    func permissionErrorLabel(_ error: String) -> String {
        SettingsAccessibility.notificationPermissionErrorLabel(error)
    }
}

struct SettingsSheetView: View {
    @State private var expression: String
    @State private var expressionError: String?
    @State private var selectedInterval: RefreshInterval
    @State private var selectedTheme: AppTheme
    @State private var profileTitle = ""
    @State private var serviceName = ""
    @State private var servicePort = ""
    @State private var serviceError: String?
    @State private var customPortProfiles: [PortProfile]
    @State private var customServiceEndpoints: [DatabaseEndpoint]
    @State private var pendingProfileDeletion: PortProfile?
    @State private var pendingServiceDeletion: DatabaseEndpoint?
    @State private var settingsError: String?
    @State private var notificationPreference: PortChangeNotificationPreference
    @State private var notificationExpressionError: String?

    @ObservedObject var viewModel: PortMonitorViewModel
    let onDismiss: () -> Void

    init(viewModel: PortMonitorViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        let draft = viewModel.makeSettingsDraft()
        _expression = State(initialValue: draft.portExpression)
        _selectedInterval = State(initialValue: draft.refreshInterval)
        _selectedTheme = State(initialValue: draft.theme)
        _customPortProfiles = State(initialValue: draft.customPortProfiles)
        _customServiceEndpoints = State(initialValue: draft.customServiceEndpoints)
        _notificationPreference = State(initialValue: draft.portChangeNotificationPreference)
        _pendingProfileDeletion = State(initialValue: nil)
        _pendingServiceDeletion = State(initialValue: nil)
        _settingsError = State(initialValue: viewModel.settingsErrorMessage)
    }

    var body: some View {
        let notificationControls = SettingsAccessibility.portChangeNotificationControls(
            isEnabled: notificationPreference.isEnabled,
            permissionStatus: viewModel.notificationPermissionStatus
        )
        let accessibility = SettingsSheetNotificationAccessibility()
        let actions = SettingsSheetActions(viewModel: viewModel, onDismiss: onDismiss)

        VStack(spacing: 0) {
            header(actions: actions)
            PTKHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: PTKSpace.lg) {
                    if let settingsError {
                        Text(settingsError)
                            .font(PTKType.ui(11))
                            .foregroundStyle(PTKTheme.danger)
                            .accessibilityLabel("설정 저장 오류: \(settingsError)")
                    }

                    watchSection(accessibility: accessibility, notificationControls: notificationControls)
                    presetsSection
                    displaySection
                    customProfilesSection
                    customServicesSection
                }
                .padding(PTKSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(selectedTheme.preferredColorScheme)
        .alert(
            "프로필 삭제",
            isPresented: Binding(
                get: { pendingProfileDeletion != nil },
                set: { if !$0 { pendingProfileDeletion = nil } }
            ),
            presenting: pendingProfileDeletion
        ) { profile in
            Button("삭제", role: .destructive) {
                customPortProfiles.removeAll { $0.id == profile.id }
                pendingProfileDeletion = nil
            }
            Button("취소", role: .cancel) {
                pendingProfileDeletion = nil
            }
        } message: { profile in
            Text("‘\(profile.title)’ 프로필을 삭제합니다.")
        }
        .alert(
            "서비스 삭제",
            isPresented: Binding(
                get: { pendingServiceDeletion != nil },
                set: { if !$0 { pendingServiceDeletion = nil } }
            ),
            presenting: pendingServiceDeletion
        ) { endpoint in
            Button("삭제", role: .destructive) {
                customServiceEndpoints.removeAll { $0.id == endpoint.id }
                pendingServiceDeletion = nil
            }
            Button("취소", role: .cancel) {
                pendingServiceDeletion = nil
            }
        } message: { endpoint in
            Text("‘\(endpoint.name)’ 서비스를 삭제합니다.")
        }
    }

    private func header(actions: SettingsSheetActions) -> some View {
        HStack(spacing: PTKSpace.md) {
            Text("설정")
                .font(PTKType.ui(13, weight: .semibold))

            Spacer(minLength: 0)

            Button("취소") {
                actions.cancel()
            }
            .buttonStyle(.plain)
            .font(PTKType.ui(12))
            .foregroundStyle(PTKTheme.muted)
            .keyboardShortcut(.cancelAction)

            Button("저장") {
                save(actions: actions)
            }
            .buttonStyle(.plain)
            .font(PTKType.ui(12, weight: .semibold))
            .foregroundStyle(
                expression.trimmingCharacters(in: .whitespaces).isEmpty
                    ? PTKTheme.faint
                    : PTKTheme.accent
            )
            .disabled(expression.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, PTKSpace.md)
        .frame(height: 36)
    }

    private func watchSection(
        accessibility: SettingsSheetNotificationAccessibility,
        notificationControls: SettingsAccessibility.PortChangeNotificationControls
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PTKSectionLabel(title: "감시")

            PTKInsetGroup {
                TextField("예: 3000-3009,5173", text: $expression)
                    .textFieldStyle(.plain)
                    .font(PTKType.mono(12))
                    .padding(PTKSpace.sm)
                    .onChange(of: expression) { _ in
                        expressionError = nil
                    }

                if let error = expressionError {
                    Text(error)
                        .font(PTKType.ui(11))
                        .foregroundStyle(PTKTheme.danger)
                        .padding(.horizontal, PTKSpace.sm)
                        .padding(.bottom, 6)
                        .accessibilityLabel("감시 포트 입력 오류: \(error)")
                }

                PTKHairline()
                    .padding(.leading, PTKSpace.sm)

                Toggle(isOn: Binding(
                    get: { notificationPreference.isEnabled },
                    set: { enabled in
                        notificationPreference = SettingsDraft.notificationPreference(
                            notificationPreference,
                            settingEnabled: enabled,
                            watchedExpression: expression
                        )
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("포트 변경 알림")
                            .font(PTKType.ui(12))
                        Text("선택한 포트가 열리거나 닫힐 때 알려줍니다.")
                            .font(PTKType.ui(11))
                            .foregroundStyle(PTKTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }
                }
                .toggleStyle(.switch)
                .padding(PTKSpace.sm)
                .accessibilityLabel(accessibility.toggleLabel)
                .accessibilityHint(accessibility.toggleHint)
                .accessibilityIdentifier(accessibility.toggleIdentifier)

                if notificationControls.showsPortExpression {
                    PTKHairline()
                        .padding(.leading, PTKSpace.sm)

                    TextField("알림 포트", text: Binding(
                        get: { notificationPreference.portsExpression ?? "" },
                        set: { notificationPreference.portsExpression = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(PTKType.mono(12))
                    .padding(PTKSpace.sm)
                    .accessibilityLabel(accessibility.expressionLabel)
                    .accessibilityHint(accessibility.expressionHint)
                    .accessibilityIdentifier(accessibility.expressionIdentifier)

                    if notificationControls.showsDeniedStatus {
                        HStack(spacing: PTKSpace.sm) {
                            Text("macOS에서 차단됨")
                                .font(PTKType.ui(11))
                                .foregroundStyle(PTKTheme.danger)
                                .accessibilityLabel(accessibility.deniedStatusLabel)
                                .accessibilityIdentifier(accessibility.deniedStatusIdentifier)
                            if notificationControls.showsSystemSettingsButton {
                                Button("시스템 설정 열기") {
                                    viewModel.openNotificationSettings()
                                }
                                .buttonStyle(.plain)
                                .font(PTKType.ui(11, weight: .medium))
                                .foregroundStyle(PTKTheme.accent)
                                .accessibilityLabel(accessibility.systemSettingsButtonLabel)
                                .accessibilityHint(accessibility.systemSettingsButtonHint)
                                .accessibilityIdentifier(accessibility.systemSettingsButtonIdentifier)
                            }
                        }
                        .padding(.horizontal, PTKSpace.sm)
                        .padding(.bottom, 8)
                    }
                    if let error = viewModel.notificationPermissionError {
                        Text(error)
                            .font(PTKType.ui(11))
                            .foregroundStyle(PTKTheme.danger)
                            .padding(.horizontal, PTKSpace.sm)
                            .padding(.bottom, 8)
                            .accessibilityLabel(accessibility.permissionErrorLabel(error))
                            .accessibilityIdentifier(accessibility.permissionErrorIdentifier)
                    }
                    if let notificationExpressionError {
                        Text(notificationExpressionError)
                            .font(PTKType.ui(11))
                            .foregroundStyle(PTKTheme.danger)
                            .padding(.horizontal, PTKSpace.sm)
                            .padding(.bottom, 8)
                            .accessibilityLabel(accessibility.validationErrorLabel(notificationExpressionError))
                            .accessibilityIdentifier(accessibility.validationErrorIdentifier)
                    }
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            PTKSectionLabel(title: "프리셋")
            PTKInsetGroup {
                ForEach(Array(viewModel.portPresets.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 {
                        PTKHairline()
                            .padding(.leading, PTKSpace.sm)
                    }
                    presetRow(preset)
                }
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            PTKSectionLabel(title: "표시")
            PTKInsetGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("새로고침 주기")
                        .font(PTKType.ui(11))
                        .foregroundStyle(PTKTheme.muted)
                    Picker(SettingsAccessibility.refreshIntervalPickerLabel, selection: $selectedInterval) {
                        ForEach(RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityHint(SettingsAccessibility.refreshIntervalPickerHint)

                    Text("테마")
                        .font(PTKType.ui(11))
                        .foregroundStyle(PTKTheme.muted)
                        .padding(.top, 4)
                    Picker(SettingsAccessibility.themePickerLabel, selection: $selectedTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityHint(SettingsAccessibility.themePickerHint)
                }
                .padding(PTKSpace.sm)
            }
        }
    }

    private var customProfilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            PTKSectionLabel(title: "사용자 프로필")
            PTKInsetGroup {
                HStack(spacing: PTKSpace.sm) {
                    TextField("프로필 이름", text: $profileTitle)
                        .textFieldStyle(.plain)
                        .font(PTKType.ui(12))
                    Button("저장") {
                        do {
                            customPortProfiles = try viewModel.addingCustomProfile(
                                title: profileTitle,
                                expression: expression,
                                to: customPortProfiles
                            )
                            profileTitle = ""
                            expressionError = nil
                        } catch {
                            expressionError = "\(error)"
                        }
                    }
                    .buttonStyle(.plain)
                    .font(PTKType.ui(12, weight: .medium))
                    .foregroundStyle(PTKTheme.accent)
                    .disabled(
                        profileTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityLabel("사용자 프로필 저장")
                    .accessibilityHint("이름 \(profileTitle)의 프로필에 현재 감시 포트를 저장합니다.")
                }
                .padding(PTKSpace.sm)

                if !customPortProfiles.isEmpty {
                    PTKHairline()
                        .padding(.leading, PTKSpace.sm)
                    ForEach(Array(customPortProfiles.enumerated()), id: \.element.id) { index, profile in
                        if index > 0 {
                            PTKHairline()
                                .padding(.leading, PTKSpace.sm)
                        }
                        customProfileRow(profile)
                    }
                }
            }
        }
    }

    private var customServicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            PTKSectionLabel(title: "서비스 포트")
            PTKInsetGroup {
                HStack(spacing: PTKSpace.sm) {
                    TextField("이름", text: $serviceName)
                        .textFieldStyle(.plain)
                        .font(PTKType.ui(12))
                    TextField("포트", text: $servicePort)
                        .textFieldStyle(.plain)
                        .font(PTKType.mono(12))
                        .frame(width: 64)
                    Button("추가") {
                        do {
                            customServiceEndpoints = try viewModel.addingCustomServiceEndpoint(
                                name: serviceName,
                                portText: servicePort,
                                to: customServiceEndpoints
                            )
                            serviceName = ""
                            servicePort = ""
                            serviceError = nil
                        } catch {
                            serviceError = "\(error)"
                        }
                    }
                    .buttonStyle(.plain)
                    .font(PTKType.ui(12, weight: .medium))
                    .foregroundStyle(PTKTheme.accent)
                    .disabled(
                        serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || servicePort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityLabel("서비스 \(serviceName) 추가")
                    .accessibilityHint("포트 \(servicePort)의 서비스를 상태 목록에 추가합니다.")
                }
                .padding(PTKSpace.sm)

                if let serviceError {
                    Text(serviceError)
                        .font(PTKType.ui(11))
                        .foregroundStyle(PTKTheme.danger)
                        .padding(.horizontal, PTKSpace.sm)
                        .padding(.bottom, 8)
                }

                if !customServiceEndpoints.isEmpty {
                    PTKHairline()
                        .padding(.leading, PTKSpace.sm)
                    ForEach(Array(customServiceEndpoints.enumerated()), id: \.element.id) { index, endpoint in
                        if index > 0 {
                            PTKHairline()
                                .padding(.leading, PTKSpace.sm)
                        }
                        customServiceRow(endpoint)
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: PortPreset) -> some View {
        let isActive = expression == preset.expression
        return Button {
            expression = preset.expression
            expressionError = nil
        } label: {
            HStack(spacing: PTKSpace.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .font(PTKType.ui(12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(PTKTheme.ink)
                        .lineLimit(1)
                    Text(preset.detail)
                        .font(PTKType.ui(11))
                        .foregroundStyle(PTKTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PTKTheme.accent)
                }
            }
            .padding(.horizontal, PTKSpace.sm)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.expression)
        .accessibilityLabel(SettingsAccessibility.presetApplyLabel(preset))
        .accessibilityHint(SettingsAccessibility.presetApplyHint(preset))
    }

    private func customProfileRow(_ profile: PortProfile) -> some View {
        HStack(spacing: PTKSpace.sm) {
            Button {
                expression = profile.expression
                expressionError = nil
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.title)
                        .font(PTKType.ui(12, weight: expression == profile.expression ? .semibold : .regular))
                        .foregroundStyle(PTKTheme.ink)
                        .lineLimit(1)
                    Text(profile.expression)
                        .font(PTKType.mono(10))
                        .foregroundStyle(PTKTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("프로필 적용: \(profile.expression)")
            .accessibilityLabel(SettingsAccessibility.profileApplyLabel(profile))
            .accessibilityHint(SettingsAccessibility.profileApplyHint(profile))

            Button {
                pendingProfileDeletion = profile
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PTKTheme.muted)
            }
            .buttonStyle(.plain)
            .help("프로필 삭제")
            .accessibilityLabel(SettingsAccessibility.profileDeleteLabel(profile))
            .accessibilityHint("이 사용자 프로필을 삭제합니다.")
        }
        .padding(.horizontal, PTKSpace.sm)
        .padding(.vertical, 8)
    }

    private func customServiceRow(_ endpoint: DatabaseEndpoint) -> some View {
        HStack(spacing: PTKSpace.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(endpoint.name)
                    .font(PTKType.ui(12, weight: .medium))
                    .foregroundStyle(PTKTheme.ink)
                    .lineLimit(1)
                Text("Port \(endpoint.port)")
                    .font(PTKType.mono(10))
                    .foregroundStyle(PTKTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                pendingServiceDeletion = endpoint
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PTKTheme.muted)
            }
            .buttonStyle(.plain)
            .help("서비스 삭제")
            .accessibilityLabel(SettingsAccessibility.serviceDeleteLabel(endpoint))
            .accessibilityHint("이 서비스 포트를 상태 목록에서 삭제합니다.")
        }
        .padding(.horizontal, PTKSpace.sm)
        .padding(.vertical, 8)
    }

    private func save(actions: SettingsSheetActions) {
        expressionError = nil
        notificationExpressionError = nil
        settingsError = nil
        do {
            try actions.save(
                SettingsDraft(
                    portExpression: expression,
                    refreshInterval: selectedInterval,
                    theme: selectedTheme,
                    customPortProfiles: customPortProfiles,
                    customServiceEndpoints: customServiceEndpoints,
                    portChangeNotificationPreference: notificationPreference
                )
            )
        } catch let error as SettingsDraftSaveError {
            switch error {
            case .watchedPorts(let error):
                expressionError = "\(error)"
            case .notificationPorts(let error):
                notificationExpressionError = "\(error)"
            case .customServices(let error):
                serviceError = "\(error)"
            case .storage(let error):
                settingsError = "\(error)"
            }
        } catch {
            settingsError = "\(error)"
        }
    }
}

enum SettingsAccessibility {
    static let refreshIntervalPickerLabel = "새로고침 주기"
    static let refreshIntervalPickerHint = "포트와 서비스 상태를 자동으로 확인할 주기를 선택합니다."
    static let themePickerLabel = "테마"
    static let themePickerHint = "PTK 화면에 사용할 밝기 테마를 선택합니다."

    static let portChangeNotificationToggleLabel = "포트 변경 알림"
    static let portChangeNotificationToggleHint = "선택한 포트가 열리거나 닫힐 때 알림을 받도록 켜거나 끕니다."
    static let portChangeNotificationToggleIdentifier = "settings.portChangeNotification.toggle"

    static let notificationPortExpressionLabel = "알림 포트"
    static let notificationPortExpressionHint = "알림을 받을 포트를 쉼표 또는 범위로 입력합니다."
    static let notificationPortExpressionIdentifier = "settings.portChangeNotification.portsExpression"

    static let notificationDeniedStatusLabel = "알림 권한이 macOS에서 차단됨"
    static let notificationDeniedStatusIdentifier = "settings.portChangeNotification.permissionDenied"

    static let notificationSystemSettingsButtonLabel = "시스템 설정 열기"
    static let notificationSystemSettingsButtonHint = "macOS 알림 설정에서 PTK 알림 권한을 변경합니다."
    static let notificationSystemSettingsButtonIdentifier = "settings.portChangeNotification.openSystemSettings"

    static func notificationValidationErrorLabel(_ error: String) -> String {
        "알림 포트 입력 오류: \(error)"
    }

    static let notificationValidationErrorIdentifier = "settings.portChangeNotification.validationError"

    static func notificationPermissionErrorLabel(_ error: String) -> String {
        "알림 설정 오류: \(error)"
    }

    static let notificationPermissionErrorIdentifier = "settings.portChangeNotification.permissionError"

    struct PortChangeNotificationControls: Equatable {
        let showsPortExpression: Bool
        let showsDeniedStatus: Bool
        let showsSystemSettingsButton: Bool
        let showsValidationError: Bool
    }

    static func portChangeNotificationControls(
        isEnabled: Bool,
        permissionStatus: PortChangeNotificationPermissionStatus,
        validationError: String? = nil
    ) -> PortChangeNotificationControls {
        let showsDeniedStatus = isEnabled && permissionStatus == .denied
        return PortChangeNotificationControls(
            showsPortExpression: isEnabled,
            showsDeniedStatus: showsDeniedStatus,
            showsSystemSettingsButton: showsDeniedStatus,
            showsValidationError: validationError != nil
        )
    }

    static func profileApplyLabel(_ profile: PortProfile) -> String {
        "프로필 \(profile.title) 적용"
    }

    static func profileApplyHint(_ profile: PortProfile) -> String {
        "감시 포트를 \(profile.expression)(으)로 변경합니다."
    }

    static func profileDeleteLabel(_ profile: PortProfile) -> String {
        "프로필 \(profile.title) 삭제"
    }

    static func serviceDeleteLabel(_ endpoint: DatabaseEndpoint) -> String {
        "서비스 \(endpoint.name), 포트 \(endpoint.port) 삭제"
    }

    static func presetApplyLabel(_ preset: PortPreset) -> String {
        "포트 프리셋 \(preset.title) 적용"
    }

    static func presetApplyHint(_ preset: PortPreset) -> String {
        "감시 포트를 \(preset.expression)(으)로 변경합니다."
    }
}
