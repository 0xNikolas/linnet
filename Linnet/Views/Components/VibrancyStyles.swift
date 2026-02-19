import SwiftUI

enum LinnetStyle {
    // Spacing
    static let sidebarWidth: CGFloat = 200
    static let nowPlayingBarHeight: CGFloat = 64
    static let gridItemMinWidth: CGFloat = 160
    static let gridItemMaxWidth: CGFloat = 200
    static let gridSpacing: CGFloat = 20
    static let contentPadding: CGFloat = 20

    // Corner radii
    static let albumArtRadius: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 6

    // Animations
    static let defaultAnimation: Animation = .easeInOut(duration: 0.2)
    static let springAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.7)

    // Shadows
    static let cardShadow: some ShapeStyle = Color.black.opacity(0.1)
    static let elevatedShadow: some ShapeStyle = Color.black.opacity(0.2)
}

extension View {
    func albumArtStyle(size: CGFloat) -> some View {
        self
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: LinnetStyle.albumArtRadius))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    func cardStyle() -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LinnetStyle.cardRadius))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
