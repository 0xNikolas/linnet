import SwiftUI
import UniformTypeIdentifiers

struct DropOverlay: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.accent, lineWidth: 3)
                    .background(.accent.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.accent)
                            Text("Drop to add to library")
                                .font(.headline)
                                .foregroundStyle(.accent)
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
