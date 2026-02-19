import SwiftUI
import SwiftData
import LinnetLibrary

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "music.note.house") }
            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "speaker.wave.3") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct LibrarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var watchedFolders: [WatchedFolder]
    @State private var libraryVM = LibraryViewModel()

    var body: some View {
        Form {
            Section("Watched Folders") {
                if watchedFolders.isEmpty {
                    Text("No folders added")
                        .foregroundStyle(.secondary)
                }
                ForEach(watchedFolders, id: \.path) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if let lastScanned = folder.lastScanned {
                            Text("Scanned \(lastScanned, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Add Folder...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        libraryVM.addFolder(url: url, context: modelContext)
                    }
                }
            }
            Section("Scanning") {
                if libraryVM.isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(libraryVM.scanProgress)
                            .font(.caption)
                    }
                }
                Button("Rescan Library") {
                    libraryVM.rescanAll(context: modelContext)
                }
                .disabled(libraryVM.isScanning || watchedFolders.isEmpty)
            }
        }
        .padding()
    }
}

struct AudioSettingsView: View {
    @State private var crossfadeEnabled = false
    @State private var crossfadeDuration: Double = 3

    var body: some View {
        Form {
            Section("Crossfade") {
                Toggle("Enable crossfade", isOn: $crossfadeEnabled)
                if crossfadeEnabled {
                    Slider(value: $crossfadeDuration, in: 1...12, step: 1) {
                        Text("\(Int(crossfadeDuration))s")
                    }
                }
            }
            Section("Volume Normalization") {
                Toggle("Enable volume normalization", isOn: .constant(false))
            }
        }
        .padding()
    }
}

struct AISettingsView: View {
    var body: some View {
        Form {
            Section("AI Models") {
                Text("No models downloaded")
                    .foregroundStyle(.secondary)
                Button("Set Up AI...") {}
            }
        }
        .padding()
    }
}
