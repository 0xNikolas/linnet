import SwiftUI
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
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 2

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text(fontSizeLabel)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSizeOffset, in: -2...6, step: 1) {
                        Text("Font Size")
                    }
                    .labelsHidden()
                    HStack {
                        Text("Smaller")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Larger")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
    }

    private var fontSizeLabel: String {
        let intOffset = Int(fontSizeOffset)
        if intOffset == 0 { return "Default" }
        if intOffset > 0 { return "+\(intOffset)" }
        return "\(intOffset)"
    }
}

struct LibrarySettingsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @State private var watchedFolders: [WatchedFolderRecord] = []
    @State private var libraryVM = LibraryViewModel()
    @State private var dbLocationChoice: String = UserDefaults.standard.string(forKey: "databaseLocationType") ?? "appSupport"
    @State private var dbLocationPath: String = UserDefaults.standard.string(forKey: "databaseLocationPath") ?? ""
    @State private var showLocationChangeAlert = false
    @State private var pendingLocation: DatabaseLocation?

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
                        if let db = appDatabase {
                            libraryVM.addFolder(url: url, db: db)
                            loadFolders()
                        }
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
                    if let db = appDatabase {
                        libraryVM.rescanAll(db: db)
                    }
                }
                .disabled(libraryVM.isScanning || watchedFolders.isEmpty)

                Button("Clear Library & Rescan") {
                    clearLibrary()
                    if let db = appDatabase {
                        libraryVM.rescanAll(db: db)
                    }
                }
                .disabled(libraryVM.isScanning || watchedFolders.isEmpty)
            }
            Section("Database Location") {
                Picker("Store database in", selection: $dbLocationChoice) {
                    Text("App Support (default)").tag("appSupport")
                    Text("Music folder").tag("musicFolder")
                    Text("Custom location...").tag("custom")
                }

                switch dbLocationChoice {
                case "musicFolder":
                    if let firstFolder = watchedFolders.first {
                        Text(firstFolder.path + "/.linnet/linnet.db")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Add a watched folder first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case "custom":
                    HStack {
                        Text(dbLocationPath.isEmpty ? "No location chosen" : dbLocationPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.message = "Choose a folder for the Linnet database"
                            if panel.runModal() == .OK, let url = panel.url {
                                dbLocationPath = url.path
                            }
                        }
                        .controlSize(.small)
                    }
                default:
                    Text(DatabaseLocation.appSupport.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Apply") {
                    applyLocationChange()
                }
                .disabled(!locationHasChanged)
            }
        }
        .padding()
        .task { loadFolders() }
        .alert("Move Database?", isPresented: $showLocationChangeAlert) {
            Button("Move & Restart", role: .destructive) {
                performLocationChange()
            }
            Button("Cancel", role: .cancel) {
                pendingLocation = nil
            }
        } message: {
            Text("The database will be copied to the new location. The app needs to restart for changes to take effect.")
        }
    }

    private func loadFolders() {
        watchedFolders = (try? appDatabase?.watchedFolders.fetchAll()) ?? []
    }

    private func removeFolder(_ folder: WatchedFolderRecord) {
        guard let db = appDatabase else { return }
        try? db.tracks.deleteByFolder(pathPrefix: folder.path)
        try? db.watchedFolders.deleteByPath(folder.path)
        try? db.albums.deleteOrphaned()
        try? db.artists.deleteOrphaned()
        loadFolders()
    }

    private func clearLibrary() {
        guard let db = appDatabase else { return }
        try? db.tracks.deleteByFolder(pathPrefix: "/")
        try? db.albums.deleteOrphaned()
        try? db.artists.deleteOrphaned()
        loadFolders()
    }

    private var locationHasChanged: Bool {
        let savedType = UserDefaults.standard.string(forKey: "databaseLocationType") ?? "appSupport"
        let savedPath = UserDefaults.standard.string(forKey: "databaseLocationPath") ?? ""
        if dbLocationChoice != savedType { return true }
        if dbLocationChoice != "appSupport" && dbLocationPath != savedPath { return true }
        return false
    }

    private func resolvedNewLocation() -> DatabaseLocation? {
        switch dbLocationChoice {
        case "musicFolder":
            guard let firstFolder = watchedFolders.first else { return nil }
            return .musicFolder(URL(filePath: firstFolder.path))
        case "custom":
            guard !dbLocationPath.isEmpty else { return nil }
            return .custom(URL(filePath: dbLocationPath).appendingPathComponent("linnet.db"))
        default:
            return .appSupport
        }
    }

    private func applyLocationChange() {
        guard let newLocation = resolvedNewLocation() else { return }
        pendingLocation = newLocation
        showLocationChangeAlert = true
    }

    private func performLocationChange() {
        guard let newLocation = pendingLocation else { return }
        let currentLocation = DatabaseLocation.saved()

        do {
            try DatabaseLocation.copyDatabase(from: currentLocation, to: newLocation)
            newLocation.save()

            // Restart the app
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-n", Bundle.main.bundlePath]
            try task.run()
            NSApplication.shared.terminate(nil)
        } catch {
            // If copy fails, don't change the setting
            pendingLocation = nil
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
