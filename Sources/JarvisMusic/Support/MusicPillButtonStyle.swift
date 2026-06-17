import SwiftUI

enum MusicPillButtonKind {
    case primary
    case secondary
}

struct MusicPillButtonModifier: ViewModifier {
    var kind: MusicPillButtonKind
    var height: CGFloat
    var horizontalPadding: CGFloat

    init(_ kind: MusicPillButtonKind = .secondary, height: CGFloat = 42, horizontalPadding: CGFloat = 18) {
        self.kind = kind
        self.height = height
        self.horizontalPadding = horizontalPadding
    }

    func body(content: Content) -> some View {
        content
            .font(MusicTypography.fixed(14, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(controlSize)
            .tint(tint)
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

    private var tint: Color {
        switch kind {
        case .primary:
            return .red
        case .secondary:
            return Color(red: 0.19, green: 0.20, blue: 0.21)
        }
    }
}

extension View {
    func musicPillButton(_ kind: MusicPillButtonKind = .secondary, height: CGFloat = 42, horizontalPadding: CGFloat = 18) -> some View {
        modifier(MusicPillButtonModifier(kind, height: height, horizontalPadding: horizontalPadding))
    }
}
