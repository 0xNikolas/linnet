import SwiftUI

struct BreadcrumbItem: Hashable {
    let title: String
    let level: Int
}

struct BreadcrumbBar: View {
    let items: [BreadcrumbItem]
    let onNavigate: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            let lastLevel = items.last?.level ?? 0
            forEachItem(items) { item in
                if item.level > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if item.level < lastLevel {
                    Button(item.title) {
                        onNavigate(item.level)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.tint)
                } else {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func forEachItem<Content: View>(_ items: [BreadcrumbItem], @ViewBuilder content: @escaping (BreadcrumbItem) -> Content) -> some View {
        let views = items.map { content($0) }
        SwiftUI.ForEach(views.indices, id: \.self) { index in
            views[index]
        }
    }
}
