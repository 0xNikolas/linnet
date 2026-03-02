import SwiftUI

struct DetailPage<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @AppStorage("showQueueSidePane") private var showQueueSidePane = false

    var body: some View {
        ScrollView {
            content()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showQueueSidePane.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
            }
        }
    }
}
