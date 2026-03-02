import SwiftUI
import LinnetLibrary

struct ListPage<S: SortOptionProtocol, Content: View>: View {
    let searchPrompt: String
    @Binding var sortOption: S
    @Binding var sortDirection: SortDirection
    @Binding var searchText: String
    var extraMenuBuilder: ((NSMenu, SortFilterMenuButton<S>.Coordinator) -> Void)?
    @ViewBuilder var content: () -> Content

    @AppStorage("showQueueSidePane") private var showQueueSidePane = false
    @State private var isSearchPresented = false

    var body: some View {
        content()
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: searchPrompt)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if let extraMenuBuilder {
                        SortFilterMenuButton(
                            sortOption: $sortOption,
                            sortDirection: $sortDirection,
                            extraMenuBuilder: extraMenuBuilder
                        )
                    } else {
                        SortFilterMenuButton(
                            sortOption: $sortOption,
                            sortDirection: $sortDirection
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showQueueSidePane.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                isSearchPresented = true
            }
    }
}
