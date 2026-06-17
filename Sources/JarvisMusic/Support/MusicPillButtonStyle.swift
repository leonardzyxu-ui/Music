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
            primaryButton(content)
        case .secondary:
            content
                .font(MusicTypography.fixed(14, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(controlSize)
                .tint(secondaryTint)
        }
    }

    @ViewBuilder
    private func primaryButton(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .font(MusicTypography.fixed(14, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.58))
                .buttonStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .glassEffect(
                    .regular.tint(primaryTint).interactive(),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    primarySpecularEdge
                }
                .shadow(color: Color.red.opacity(isEnabled ? 0.18 : 0), radius: 9, x: -2, y: 3)
                .contentShape(Capsule(style: .continuous))
        } else {
            content
                .font(MusicTypography.fixed(14, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.58))
                .buttonStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background {
                    Capsule(style: .continuous)
                        .fill(primaryTint)
                    primarySpecularEdge
                }
                .shadow(color: Color.red.opacity(isEnabled ? 0.18 : 0), radius: 9, x: -2, y: 3)
                .contentShape(Capsule(style: .continuous))
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

    private var primaryTint: Color {
        Color(red: 1.0, green: 0.13, blue: 0.18).opacity(isEnabled ? 0.82 : 0.32)
    }

    private var primarySpecularEdge: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isEnabled ? 0.34 : 0.10), location: 0),
                        .init(color: Color.white.opacity(isEnabled ? 0.10 : 0.04), location: 0.28),
                        .init(color: Color.clear, location: 0.56),
                        .init(color: Color.black.opacity(isEnabled ? 0.18 : 0.09), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
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
