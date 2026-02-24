import SwiftUI
import AppKit

/// Detects single and double clicks via NSView overlay,
/// avoiding conflicts between SwiftUI's `.onTapGesture` and AppKit click handling.
struct ClickOverlay: NSViewRepresentable {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }

    class ClickView: NSView {
        var onSingleClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            if event.clickCount == 2 {
                onDoubleClick?()
            } else if event.clickCount == 1 {
                onSingleClick?()
            }
        }
    }
}

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        overlay(ClickOverlay(onDoubleClick: action))
    }

    func onClicks(single: @escaping () -> Void, double: @escaping () -> Void) -> some View {
        overlay(ClickOverlay(onSingleClick: single, onDoubleClick: double))
    }
}
