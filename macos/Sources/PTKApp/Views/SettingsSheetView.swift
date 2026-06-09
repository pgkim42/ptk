import SwiftUI
import PTKCore

struct SettingsSheetView: View {
    @State private var expression: String
    @State private var expressionError: String?
    @State private var selectedInterval: RefreshInterval
    @State private var selectedTheme: AppTheme
    @State private var profileTitle = ""
    @State private var serviceName = ""
    @State private var servicePort = ""
    @State private var serviceError: String?

    @ObservedObject var viewModel: PortMonitorViewModel
    let onDismiss: () -> Void

    init(viewModel: PortMonitorViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _expression = State(initialValue: viewModel.portExpression)
        _selectedInterval = State(initialValue: viewModel.refreshInterval)
        _selectedTheme = State(initialValue: viewModel.theme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("설정")
                .font(.headline)

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
                Picker("", selection: $selectedInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("테마").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTheme) { theme in
                    viewModel.saveTheme(theme)
                }
            }

            HStack {
                Button("취소") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("저장") {
                    do {
                        try viewModel.saveExpression(expression)
                        viewModel.saveInterval(selectedInterval)
                        viewModel.saveTheme(selectedTheme)
                        onDismiss()
                    } catch {
                        expressionError = "\(error)"
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
        .preferredColorScheme(viewModel.theme.preferredColorScheme)
    }

    private var customProfilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("사용자 프로필").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("프로필 이름", text: $profileTitle)
                    .textFieldStyle(.roundedBorder)

                Button("저장") {
                    do {
                        try viewModel.saveCustomProfile(title: profileTitle, expression: expression)
                        profileTitle = ""
                        expressionError = nil
                    } catch {
                        expressionError = "\(error)"
                    }
                }
                .disabled(profileTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !viewModel.customPortProfiles.isEmpty {
                VStack(spacing: 6) {
                    ForEach(viewModel.customPortProfiles) { profile in
                        customProfileRow(profile)
                    }
                }
            }
        }
    }

    private func customProfileRow(_ profile: PortProfile) -> some View {
        HStack(spacing: 6) {
            Button {
                do {
                    try viewModel.applyProfile(profile)
                    expression = profile.expression
                    expressionError = nil
                } catch {
                    expressionError = "\(error)"
                }
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

            Button {
                viewModel.deleteCustomProfile(profile)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("프로필 삭제")
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
                        try viewModel.saveCustomServiceEndpoint(name: serviceName, portText: servicePort)
                        serviceName = ""
                        servicePort = ""
                        serviceError = nil
                    } catch {
                        serviceError = "\(error)"
                    }
                }
                .disabled(serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || servicePort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let serviceError {
                Text(serviceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !viewModel.customServiceEndpoints.isEmpty {
                VStack(spacing: 6) {
                    ForEach(viewModel.customServiceEndpoints) { endpoint in
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
                viewModel.deleteCustomServiceEndpoint(endpoint)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("서비스 삭제")
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
    }
}
