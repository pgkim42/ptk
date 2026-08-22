import SwiftUI

struct PTKHairline: View {
    var body: some View {
        Rectangle()
            .fill(PTKTheme.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct PTKInsetGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: PTKTheme.radiusGroup, style: .continuous)
                    .fill(PTKTheme.lift)
            )
    }
}

struct PTKSectionLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: PTKSpace.sm) {
            Text(title)
                .font(PTKType.ui(11, weight: .semibold))
                .foregroundStyle(PTKTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .font(PTKType.mono(11))
                    .foregroundStyle(PTKTheme.faint)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

struct PanelSectionHeaderView: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        PTKSectionLabel(title: title, trailing: trailing)
    }
}

struct PanelServiceGroupHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PTKType.ui(10, weight: .semibold))
            .foregroundStyle(PTKTheme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PTKSpace.sm)
            .frame(height: ServiceStatusListMetrics.groupHeaderHeight)
    }
}

struct PTKStatusDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

struct PanelIconButton: View {
    let systemName: String
    let help: String
    let accessibilityHint: String
    var tint: Color = PTKTheme.muted
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(PTKIconButtonStyle(tint: tint, size: 24))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityHint(accessibilityHint)
    }
}

struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: PTKSpace.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PTKTheme.caution)
            Text(message)
                .font(PTKType.ui(11))
                .foregroundStyle(PTKTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(PTKSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: PTKTheme.radiusGroup, style: .continuous)
                .fill(PTKTheme.caution.opacity(0.12))
        )
        .accessibilityLabel("오류: \(message)")
    }
}
