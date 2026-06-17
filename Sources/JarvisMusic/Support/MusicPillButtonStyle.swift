import SwiftUI

enum MusicPillButtonKind {
    case primary
    case secondary
}

struct MusicPillButtonStyle: ButtonStyle {
    var kind: MusicPillButtonKind
    var height: CGFloat
    var horizontalPadding: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    init(_ kind: MusicPillButtonKind = .secondary, height: CGFloat = 42, horizontalPadding: CGFloat = 18) {
        self.kind = kind
        self.height = height
        self.horizontalPadding = horizontalPadding
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MusicTypography.fixed(14, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 0.98 : 0.42))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background {
                Capsule(style: .continuous)
                    .fill(baseFill.opacity(isEnabled ? 1 : 0.48))
                Capsule(style: .continuous)
                    .fill(buttonLight(configuration: configuration))
                    .blendMode(.screen)
                Capsule(style: .continuous)
                    .stroke(borderLight, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: kind == .primary ? 9 : 5, y: kind == .primary ? 4 : 2)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }

    private var baseFill: Color {
        switch kind {
        case .primary:
            return .red
        case .secondary:
            return Color.white.opacity(0.105)
        }
    }

    private func buttonLight(configuration: Configuration) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(configuration.isPressed ? 0.20 : 0.28),
                Color.white.opacity(configuration.isPressed ? 0.08 : 0.14),
                Color.clear,
                Color.black.opacity(kind == .primary ? 0.10 : 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderLight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(kind == .primary ? 0.25 : 0.18),
                Color.white.opacity(0.05),
                Color.black.opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowColor: Color {
        switch kind {
        case .primary:
            return .red.opacity(0.20)
        case .secondary:
            return .black.opacity(0.20)
        }
    }
}
