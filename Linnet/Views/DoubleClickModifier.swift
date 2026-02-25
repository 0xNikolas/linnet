import SwiftUI

// MARK: - Button-based click detection

/// Uses a plain Button for reliable click handling on macOS.
/// Single-click fires immediately. Double-click detected via timing.
private struct ClicksModifier: ViewModifier {
    let single: () -> Void
    let double: () -> Void
    @State private var lastClickTime: Date = .distantPast

    func body(content: Content) -> some View {
        Button {
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < NSEvent.doubleClickInterval {
                lastClickTime = .distantPast
                double()
            } else {
                lastClickTime = now
                single()
            }
        } label: {
            content
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View extensions

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        modifier(ClicksModifier(single: {}, double: action))
    }

    func onClicks(single: @escaping () -> Void, double: @escaping () -> Void) -> some View {
        modifier(ClicksModifier(single: single, double: double))
    }
}
