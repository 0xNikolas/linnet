import SwiftUI

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        onTapGesture(count: 2, perform: action)
    }

    func onClicks(single: @escaping () -> Void, double: @escaping () -> Void) -> some View {
        onTapGesture(count: 2, perform: double)
            .onTapGesture(count: 1, perform: single)
    }
}
