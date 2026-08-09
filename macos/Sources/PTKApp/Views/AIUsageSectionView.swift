import SwiftUI
import PTKCore

typealias AIUsageSnapshotProvider = @Sendable () async -> AIUsageSnapshot

struct AIUsageSectionView: View {
    private static let monitor = AIUsageMonitor()
    static let liveSnapshotProvider: AIUsageSnapshotProvider = {
        await monitor.snapshot()
    }

    let snapshotProvider: AIUsageSnapshotProvider
    @State private var providers: [AIUsageProviderStatus] = [
        .init(provider: .claude, windows: [], errorMessage: "확인 중"),
        .init(provider: .codex, windows: [], errorMessage: "확인 중")
    ]
    @State private var isLoading = true

    init(snapshotProvider: @escaping AIUsageSnapshotProvider = Self.liveSnapshotProvider) {
        self.snapshotProvider = snapshotProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI Credits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PTKTheme.muted)
                Text("남은 한도")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PTKTheme.faint)
                Spacer()
                if isLoading { ProgressView().controlSize(.mini) }
            }

            HStack(spacing: 8) {
                ForEach(providers, id: \.provider.rawValue) { provider in
                    providerCard(provider)
                }
                if providers.isEmpty && !isLoading {
                    Text("잔여량을 확인할 수 없습니다")
                        .font(.system(size: 11))
                        .foregroundStyle(PTKTheme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(AIUsageMonitor.refreshInterval))
            }
        }
    }

    private func providerCard(_ provider: AIUsageProviderStatus) -> some View {
        let accent = accentColor(for: provider.provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbolName(for: provider.provider))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(provider.provider.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Circle()
                    .fill(provider.errorMessage == nil ? PTKTheme.green : PTKTheme.orange)
                    .frame(width: 6, height: 6)
            }

            if let error = provider.errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: isLoading ? "ellipsis" : "exclamationmark.circle")
                    Text(error)
                        .lineLimit(1)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PTKTheme.faint)
            } else {
                ForEach(provider.windows, id: \.label) { window in
                    remainingRow(window, accent: accent)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PTKTheme.card)
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        colors: [accent.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        }
    }

    private func remainingRow(_ window: AIUsageWindow, accent: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(window.label)
                    .foregroundStyle(PTKTheme.muted)
                Spacer()
                if let percentage = window.remainingPercentage {
                    Text("\(Int(percentage.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(percentage <= 20 ? PTKTheme.orange : PTKTheme.text)
                } else {
                    Text("—").foregroundStyle(PTKTheme.faint)
                }
            }
            .font(.system(size: 9, weight: .semibold))

            GeometryReader { geometry in
                let remaining = min(100, max(0, window.remainingPercentage ?? 0))
                ZStack(alignment: .leading) {
                    Capsule().fill(PTKTheme.border)
                    Capsule()
                        .fill(remaining <= 20 ? PTKTheme.orange : accent)
                        .frame(width: geometry.size.width * remaining / 100)
                }
            }
            .frame(height: 4)
        }
        .help(resetHelp(window.resetsAt))
    }

    private func accentColor(for provider: AIUsageProviderStatus.Provider) -> Color {
        switch provider {
        case .claude: Color(red: 0.86, green: 0.48, blue: 0.30)
        case .codex: PTKTheme.blue
        }
    }

    private func symbolName(for provider: AIUsageProviderStatus.Provider) -> String {
        switch provider {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }

    private func resetHelp(_ date: Date?) -> String {
        guard let date else { return "초기화 시각 정보 없음" }
        return "초기화: \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    @MainActor
    private func reload() async {
        isLoading = true
        providers = await snapshotProvider().providers
        isLoading = false
    }
}
