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
            ArtworkSettingsView()
                .tabItem { Label("Artwork", systemImage: "photo") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 450, height: 350)
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
                        Button(action: {
                            removeFolder(folder)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
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

                Button("Clear Library & Rescan") {
                    clearLibrary()
                    libraryVM.rescanAll(context: modelContext)
                }
                .disabled(libraryVM.isScanning || watchedFolders.isEmpty)
            }
        }
        .padding()
    }

    private func removeFolder(_ folder: WatchedFolder) {
        // Remove tracks that belong to this folder
        let folderPath = folder.path
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.filePath.starts(with: folderPath) })
        if let tracks = try? modelContext.fetch(descriptor) {
            for track in tracks {
                modelContext.delete(track)
            }
        }
        modelContext.delete(folder)
        cleanupOrphanedArtistsAndAlbums()
        try? modelContext.save()
    }

    private func clearLibrary() {
        try? modelContext.fetch(FetchDescriptor<Track>()).forEach { modelContext.delete($0) }
        try? modelContext.fetch(FetchDescriptor<Album>()).forEach { modelContext.delete($0) }
        try? modelContext.fetch(FetchDescriptor<Artist>()).forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    private func cleanupOrphanedArtistsAndAlbums() {
        if let albums = try? modelContext.fetch(FetchDescriptor<Album>()) {
            for album in albums where album.tracks.isEmpty {
                modelContext.delete(album)
            }
        }
        if let artists = try? modelContext.fetch(FetchDescriptor<Artist>()) {
            for artist in artists where artist.tracks.isEmpty {
                modelContext.delete(artist)
            }
        }
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

struct ArtworkSettingsView: View {
    @AppStorage("acoustIDAPIKey") private var acoustIDKey = ""
    @AppStorage("fanartTVAPIKey") private var fanartTVKey = ""

    var body: some View {
        Form {
            Section("Album Artwork") {
                Text("Album covers are fetched automatically from MusicBrainz and Cover Art Archive (no API key needed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("AcoustID API Key") {
                    SecureField("Optional — enables fingerprint fallback", text: $acoustIDKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Get a free key at acoustid.org")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Artist Images") {
                Text("Artist photos are fetched from Wikipedia (no API key needed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Fanart.tv API Key") {
                    SecureField("Optional — enables higher-quality images", text: $fanartTVKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Get a free key at fanart.tv")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
