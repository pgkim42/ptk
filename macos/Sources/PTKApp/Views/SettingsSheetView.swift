import SwiftUI
import PTKCore

struct SettingsSheetView: View {
    @State private var expression: String
    @State private var expressionError: String?
    @State private var selectedInterval: RefreshInterval

    let viewModel: PortMonitorViewModel
    let onDismiss: () -> Void

    init(viewModel: PortMonitorViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _expression = State(initialValue: viewModel.portExpression)
        _selectedInterval = State(initialValue: viewModel.refreshInterval)
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

            VStack(alignment: .leading, spacing: 4) {
                Text("새로고침 주기").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $selectedInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
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
    }
}
