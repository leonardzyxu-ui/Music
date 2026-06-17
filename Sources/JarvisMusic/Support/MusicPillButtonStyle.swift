import SwiftUI

enum MusicPillButtonKind {
    case primary
    case secondary
}

struct MusicPillButtonModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    var kind: MusicPillButtonKind
    var height: CGFloat
    var horizontalPadding: CGFloat

    init(_ kind: MusicPillButtonKind = .secondary, height: CGFloat = 42, horizontalPadding: CGFloat = 18) {
        self.kind = kind
        self.height = height
        self.horizontalPadding = horizontalPadding
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch kind {
        case .primary:
            content
                .font(MusicTypography.fixed(14, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.58))
                .buttonStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background {
                    Capsule(style: .continuous)
                        .fill(primaryBase)
                    Capsule(style: .continuous)
                        .fill(primaryLighting)
                        .blendMode(.screen)
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isEnabled ? 0.17 : 0.07), lineWidth: 1)
                }
                .shadow(color: Color.red.opacity(isEnabled ? 0.22 : 0), radius: 10, x: -2, y: 3)
                .contentShape(Capsule(style: .continuous))
        case .secondary:
            content
                .font(MusicTypography.fixed(14, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(controlSize)
                .tint(secondaryTint)
        }
    }

    private var controlSize: ControlSize {
        if height <= 34 {
            return .small
        }
        if height <= 38 {
            return .regular
        }
        return .large
    }

    private var primaryBase: Color {
        Color(red: 1.0, green: 0.18, blue: 0.22).opacity(isEnabled ? 1 : 0.48)
    }

    private var primaryLighting: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isEnabled ? 0.32 : 0.12), location: 0),
                .init(color: Color.white.opacity(isEnabled ? 0.10 : 0.04), location: 0.42),
                .init(color: Color.clear, location: 0.58),
                .init(color: Color.black.opacity(isEnabled ? 0.18 : 0.10), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var secondaryTint: Color {
        Color(red: 0.19, green: 0.20, blue: 0.21)
    }
}

extension View {
    func musicPillButton(_ kind: MusicPillButtonKind = .secondary, height: CGFloat = 42, horizontalPadding: CGFloat = 18) -> some View {
        modifier(MusicPillButtonModifier(kind, height: height, horizontalPadding: horizontalPadding))
    }
}
