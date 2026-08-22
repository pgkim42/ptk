import SwiftUI

struct PTKIconButtonVisualState: Equatable {
    let isHovering: Bool
    let isPressed: Bool
    let isFocused: Bool
    let isDisabled: Bool

    init(
        isHovering: Bool,
        isPressed: Bool,
        isFocused: Bool = false,
        isDisabled: Bool = false
    ) {
        self.isHovering = isHovering
        self.isPressed = isPressed
        self.isFocused = isFocused
        self.isDisabled = isDisabled
    }

    var scale: CGFloat {
        if isDisabled { return 1 }
        return isPressed ? 0.98 : 1
    }

    var backgroundOpacity: Double {
        if isDisabled { return 0 }
        if isPressed { return 0.16 }
        return isHovering ? 0.08 : 0
    }

    var iconOpacity: Double {
        if isDisabled { return 0.45 }
        if isPressed { return 1 }
        return isHovering ? 0.92 : 0.78
    }
}

struct PTKIconButtonStyle: ButtonStyle {
    let tint: Color
    let size: CGFloat

    init(tint: Color = PTKTheme.muted, size: CGFloat = 24) {
        self.tint = tint
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        PTKIconButtonStyleBody(configuration: configuration, tint: tint, size: size)
    }
}

private struct PTKIconButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let size: CGFloat
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PTKIconButtonSurface(
            tint: tint,
            size: size,
            state: PTKIconButtonVisualState(
                isHovering: isHovering,
                isPressed: configuration.isPressed,
                isFocused: isFocused,
                isDisabled: !isEnabled
            )
        ) {
            configuration.label
        }
        .onHover { isHovering = $0 }
        .animation(PTKMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
        .animation(PTKMotion.micro(reduceMotion: reduceMotion), value: isHovering)
    }
}

private struct PTKIconButtonSurface<Label: View>: View {
    let tint: Color
    let size: CGFloat
    let state: PTKIconButtonVisualState
    let label: Label

    init(
        tint: Color,
        size: CGFloat,
        state: PTKIconButtonVisualState,
        @ViewBuilder label: () -> Label
    ) {
        self.tint = tint
        self.size = size
        self.state = state
        self.label = label()
    }

    var body: some View {
        label
            .foregroundStyle(tint.opacity(state.iconOpacity))
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: PTKTheme.radiusControl, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: PTKTheme.radiusControl, style: .continuous)
                    .fill(tint.opacity(state.backgroundOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PTKTheme.radiusControl + 2, style: .continuous)
                    .stroke(state.isFocused ? PTKTheme.focus : Color.clear, lineWidth: 2)
            }
            .scaleEffect(state.scale)
    }
}

struct PTKButtonInteractionPreview: View {
    var body: some View {
        HStack(spacing: PTKSpace.lg) {
            previewButton(
                title: "대기",
                systemName: "gearshape",
                tint: PTKTheme.muted,
                state: PTKIconButtonVisualState(isHovering: false, isPressed: false)
            )
            previewButton(
                title: "호버",
                systemName: "arrow.clockwise",
                tint: PTKTheme.muted,
                state: PTKIconButtonVisualState(isHovering: true, isPressed: false)
            )
            previewButton(
                title: "누름",
                systemName: "xmark",
                tint: PTKTheme.danger,
                state: PTKIconButtonVisualState(isHovering: true, isPressed: true)
            )
        }
        .padding(PTKSpace.lg)
        .background(PTKTheme.paper)
    }

    private func previewButton(
        title: String,
        systemName: String,
        tint: Color,
        state: PTKIconButtonVisualState
    ) -> some View {
        VStack(spacing: PTKSpace.sm) {
            PTKIconButtonSurface(tint: tint, size: 28, state: state) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(PTKType.ui(10, weight: .medium))
                .foregroundStyle(PTKTheme.faint)
        }
        .frame(width: 52)
    }
}
