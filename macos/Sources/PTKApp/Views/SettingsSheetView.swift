import SwiftUI
import PTKCore

struct SettingsSheetView: View {
    @State private var expression: String
    @State private var expressionError: String?
    @State private var selectedInterval: RefreshInterval
    @State private var selectedTheme: AppTheme

    let viewModel: PortMonitorViewModel
    let onDismiss: () -> Void

    init(viewModel: PortMonitorViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _expression = State(initialValue: viewModel.portExpression)
        _selectedInterval = State(initialValue: viewModel.refreshInterval)
        _selectedTheme = State(initialValue: viewModel.theme)
    }

    var body: some View {
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
        .padding()
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(viewModel.theme.preferredColorScheme)
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
