import SwiftUI

struct PanelIconButton: View {
    let systemName: String
    let help: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(PTKIconButtonStyle(tint: PTKTheme.muted, size: 24))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityHint(accessibilityHint)
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
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PTKTheme.faint)
                .lineLimit(1)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PTKTheme.faint)
                    .lineLimit(1)
            }
        }
        .frame(height: 12)
    }
}

struct PanelServiceGroupHeaderView: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PTKTheme.faint)
            Spacer()
        }
        .padding(.horizontal, 9)
        .frame(height: 18)
        .background(PTKTheme.card.opacity(0.55))
    }
}

struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PTKTheme.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(PTKTheme.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PTKTheme.orange.opacity(0.12)))
    }
}
