import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    @AppStorage("sidebarConfiguration") private var configuration: SidebarConfiguration = .default
    @State private var showEditSheet = false

    var body: some View {
        List(selection: $selectedItem) {
            Section("Library") {
                ForEach(configuration.visibleItems, id: \.self) { item in
                    Label(item.label, systemImage: item.systemImage)
                        .tag(item)
                        .contextMenu {
                            Button("Hide \"\(item.label)\"") {
                                setVisibility(of: item, visible: false)
                            }
                            Divider()
                            Button("Edit Sidebar...") {
                                showEditSheet = true
                            }
                        }
                }
                .onMove { source, destination in
                    moveVisibleItems(from: source, to: destination)
                }
            }

            Section("Playlists") {
                // Placeholder — will be populated from SwiftData later
                Label("New Playlist...", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            configuration.mergeDefaults()
        }
        .sheet(isPresented: $showEditSheet) {
            EditSidebarSheet(configuration: $configuration)
        }
    }

    // MARK: - Helpers

    private func setVisibility(of item: SidebarItem, visible: Bool) {
        guard let index = configuration.entries.firstIndex(where: { $0.item == item }) else { return }
        configuration.entries[index].isVisible = visible
        // If we hid the selected item, clear selection
        if !visible && selectedItem == item {
            selectedItem = configuration.visibleItems.first
        }
    }

    /// Map a move in the visible-only list back to the full entries array.
    private func moveVisibleItems(from source: IndexSet, to destination: Int) {
        var visible = configuration.visibleItems
        visible.move(fromOffsets: source, toOffset: destination)

        // Rebuild entries: keep hidden items in their relative position among visible ones.
        // Strategy: replace the ordering of visible items while keeping hidden items attached
        // after their preceding visible item.
        var newEntries: [SidebarConfiguration.Entry] = []
        let hiddenEntries = configuration.entries.filter { !$0.isVisible }

        // Build a mapping from each visible item to hidden items that originally followed it.
        var hiddenAfter: [SidebarItem: [SidebarConfiguration.Entry]] = [:]
        var hiddenBefore: [SidebarConfiguration.Entry] = [] // hidden items before any visible item
        var lastVisible: SidebarItem?
        for entry in configuration.entries {
            if entry.isVisible {
                lastVisible = entry.item
            } else {
                if let lv = lastVisible {
                    hiddenAfter[lv, default: []].append(entry)
                } else {
                    hiddenBefore.append(entry)
                }
            }
        }

        // Reconstruct: leading hidden items, then each visible item followed by its hidden items.
        newEntries.append(contentsOf: hiddenBefore)
        for item in visible {
            newEntries.append(SidebarConfiguration.Entry(item: item, isVisible: true))
            if let trailing = hiddenAfter[item] {
                newEntries.append(contentsOf: trailing)
            }
        }

        configuration.entries = newEntries
    }
}

// MARK: - Edit Sidebar Sheet

struct EditSidebarSheet: View {
    @Binding var configuration: SidebarConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Sidebar")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Item list
            List {
                ForEach($configuration.entries) { $entry in
                    HStack {
                        Toggle(isOn: $entry.isVisible) {
                            Label(entry.item.label, systemImage: entry.item.systemImage)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .onMove { source, destination in
                    configuration.entries.move(fromOffsets: source, toOffset: destination)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Reset to Default") {
                    configuration = .default
                }
                Spacer()
            }
            .padding()
        }
        .frame(width: 320, height: 380)
    }
}
