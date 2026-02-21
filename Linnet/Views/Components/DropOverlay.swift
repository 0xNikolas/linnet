import SwiftUI
import UniformTypeIdentifiers

struct DropOverlay: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.tint)
                            Text("Drop to add to library")
                                .font(.headline)
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(4)
            }
        }
    }
}

extension View {
    func dropOverlay(isTargeted: Bool) -> some View {
        modifier(DropOverlay(isTargeted: isTargeted))
    }
}
