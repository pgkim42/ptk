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
        ScrollView {
            VStack(spacing: 16) {
                let notificationControls = SettingsAccessibility.portChangeNotificationControls(
                    isEnabled: notificationPreference.isEnabled,
                    permissionStatus: viewModel.notificationPermissionStatus
                )
                let accessibility = SettingsSheetNotificationAccessibility()
                let actions = SettingsSheetActions(viewModel: viewModel, onDismiss: onDismiss)

                Text("설정")
                .font(.headline)

                if let settingsError {
                    Text(settingsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("설정 저장 오류: \(settingsError)")
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("감시 포트").font(.caption).foregroundStyle(.secondary)
                TextField("예: 3000-3009,5173", text: $expression)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: expression) { _ in
                        expressionError = nil
                    }
                if let error = expressionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("감시 포트 입력 오류: \(error)")
                }
            }
            VStack(alignment: .leading, spacing: 4) {

                Toggle("포트 변경 알림", isOn: Binding(
                    get: { notificationPreference.isEnabled },
                    set: { enabled in
                        notificationPreference = SettingsDraft.notificationPreference(
                            notificationPreference,
                            settingEnabled: enabled,
                            watchedExpression: expression
                        )
                    }
                ))
                .accessibilityLabel(accessibility.toggleLabel)
                .accessibilityHint(accessibility.toggleHint)
                .accessibilityIdentifier(accessibility.toggleIdentifier)

                Text("선택한 포트가 열리거나 닫힐 때 알려줍니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                if notificationControls.showsPortExpression {
                    TextField("알림 포트", text: Binding(
                        get: { notificationPreference.portsExpression ?? "" },
                        set: { notificationPreference.portsExpression = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(accessibility.expressionLabel)
                    .accessibilityHint(accessibility.expressionHint)
                    .accessibilityIdentifier(accessibility.expressionIdentifier)

                    if notificationControls.showsDeniedStatus {
                        HStack {
                            Text("macOS에서 차단됨")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel(accessibility.deniedStatusLabel)
                                .accessibilityIdentifier(accessibility.deniedStatusIdentifier)
                            if notificationControls.showsSystemSettingsButton {
                                Button("시스템 설정 열기") {
                                    viewModel.openNotificationSettings()
                                }
                                .accessibilityLabel(accessibility.systemSettingsButtonLabel)
                                .accessibilityHint(accessibility.systemSettingsButtonHint)
                                .accessibilityIdentifier(accessibility.systemSettingsButtonIdentifier)
                            }
                        }
                    }
                    if let error = viewModel.notificationPermissionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(accessibility.permissionErrorLabel(error))
                            .accessibilityIdentifier(accessibility.permissionErrorIdentifier)
                    }
                    if let notificationExpressionError {
                        Text(notificationExpressionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(accessibility.validationErrorLabel(notificationExpressionError))
                            .accessibilityIdentifier(accessibility.validationErrorIdentifier)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("포트 프리셋").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(viewModel.portPresets) { preset in
                        presetButton(preset)
                    }
                }
            }

            customProfilesSection
            customServicesSection


            VStack(alignment: .leading, spacing: 4) {
                Text("새로고침 주기").font(.caption).foregroundStyle(.secondary)
                Picker(SettingsAccessibility.refreshIntervalPickerLabel, selection: $selectedInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityHint(SettingsAccessibility.refreshIntervalPickerHint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("테마").font(.caption).foregroundStyle(.secondary)
                Picker(SettingsAccessibility.themePickerLabel, selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityHint(SettingsAccessibility.themePickerHint)
            }

            HStack {
                Button("취소") {
                    actions.cancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("저장") {
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
                        case .storage(let error):
                            settingsError = "\(error)"
                        }
                    } catch {
                        settingsError = "\(error)"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(expression.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        }
        .padding()
        .frame(width: 320)
        .frame(maxHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var customProfilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("사용자 프로필").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("프로필 이름", text: $profileTitle)
                    .textFieldStyle(.roundedBorder)

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
                .disabled(profileTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("사용자 프로필 저장")
                .accessibilityHint("이름 \(profileTitle)의 프로필에 현재 감시 포트를 저장합니다.")
            }

            if !customPortProfiles.isEmpty {
                VStack(spacing: 6) {
                    ForEach(customPortProfiles) { profile in
                        customProfileRow(profile)
                    }
                }
            }
        }
    }

    private func customProfileRow(_ profile: PortProfile) -> some View {
        HStack(spacing: 6) {
            Button {
                expression = profile.expression
                expressionError = nil
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(profile.expression)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(expression == profile.expression ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(expression == profile.expression ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.14), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .help("프로필 적용: \(profile.expression)")
            .accessibilityLabel(SettingsAccessibility.profileApplyLabel(profile))
            .accessibilityHint(SettingsAccessibility.profileApplyHint(profile))

            Button {
                pendingProfileDeletion = profile
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("프로필 삭제")
            .accessibilityLabel(SettingsAccessibility.profileDeleteLabel(profile))
            .accessibilityHint("이 사용자 프로필을 삭제합니다.")
        }
    }

    private var customServicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("서비스 포트").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("이름", text: $serviceName)
                    .textFieldStyle(.roundedBorder)
                TextField("포트", text: $servicePort)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 72)

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
                .disabled(serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || servicePort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("서비스 \(serviceName) 추가")
                .accessibilityHint("포트 \(servicePort)의 서비스를 상태 목록에 추가합니다.")
            }

            if let serviceError {
                Text(serviceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !customServiceEndpoints.isEmpty {
                VStack(spacing: 6) {
                    ForEach(customServiceEndpoints) { endpoint in
                        customServiceRow(endpoint)
                    }
                }
            }
        }
    }

    private func customServiceRow(_ endpoint: DatabaseEndpoint) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Port \(endpoint.port)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
            }

            Button {
                pendingServiceDeletion = endpoint
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("서비스 삭제")
            .accessibilityLabel(SettingsAccessibility.serviceDeleteLabel(endpoint))
            .accessibilityHint("이 서비스 포트를 상태 목록에서 삭제합니다.")
        }
    }
    private func presetButton(_ preset: PortPreset) -> some View {
        let isActive = expression == preset.expression
        return Button {
            expression = preset.expression
            expressionError = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(preset.detail)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(preset.expression)
        .accessibilityLabel(SettingsAccessibility.presetApplyLabel(preset))
        .accessibilityHint(SettingsAccessibility.presetApplyHint(preset))
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
