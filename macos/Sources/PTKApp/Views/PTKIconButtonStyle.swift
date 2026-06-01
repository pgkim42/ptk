import SwiftUI

struct PTKIconButtonVisualState: Equatable {
    let isHovering: Bool
    let isPressed: Bool

    var scale: CGFloat {
        if isPressed { return 0.92 }
        return isHovering ? 1.05 : 1.0
    }

    var backgroundOpacity: Double {
        if isPressed { return 0.22 }
        return isHovering ? 0.13 : 0.0
    }

    var borderOpacity: Double {
        if isPressed { return 0.28 }
        return isHovering ? 0.20 : 0.0
    }

    var iconOpacity: Double {
        if isPressed { return 1.0 }
        return isHovering ? 0.92 : 0.72
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

    var body: some View {
        PTKIconButtonSurface(
            tint: tint,
            size: size,
            state: PTKIconButtonVisualState(isHovering: isHovering, isPressed: configuration.isPressed)
        ) {
            configuration.label
        }
        .onHover { isHovering = $0 }
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
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(state.backgroundOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(state.borderOpacity), lineWidth: 1)
            }
            .scaleEffect(state.scale)
            .animation(.easeOut(duration: 0.12), value: state)
    }
}

struct PTKButtonInteractionPreview: View {
    var body: some View {
        HStack(spacing: 18) {
            previewButton(
                title: "Idle",
                systemName: "gearshape",
                tint: PTKTheme.muted,
                state: PTKIconButtonVisualState(isHovering: false, isPressed: false)
            )
            previewButton(
                title: "Hover",
                systemName: "arrow.clockwise",
                tint: PTKTheme.muted,
                state: PTKIconButtonVisualState(isHovering: true, isPressed: false)
            )
            previewButton(
                title: "Press",
                systemName: "xmark",
                tint: PTKTheme.red,
                state: PTKIconButtonVisualState(isHovering: true, isPressed: true)
            )
        }
        .padding(18)
        .background(PTKTheme.panel)
    }

    private func previewButton(
        title: String,
        systemName: String,
        tint: Color,
        state: PTKIconButtonVisualState
    ) -> some View {
        VStack(spacing: 8) {
            PTKIconButtonSurface(tint: tint, size: 30, state: state) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PTKTheme.faint)
        }
        .frame(width: 52)
    }
}
