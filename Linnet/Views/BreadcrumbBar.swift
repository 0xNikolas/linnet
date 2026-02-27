import SwiftUI

struct BreadcrumbItem: Hashable {
    let title: String
    let level: Int
}

struct NavigationBar: View {
    let breadcrumbs: [BreadcrumbItem]
    let onHome: () -> Void
    let onBack: () -> Void

    private var previousItem: BreadcrumbItem? {
        guard breadcrumbs.count >= 2 else { return nil }
        return breadcrumbs[breadcrumbs.count - 2]
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onHome) {
                Image(systemName: "house")
                    .font(.app(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            if let previous = previousItem {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.app(size: 11))
                        Text(previous.title)
                            .font(.app(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
