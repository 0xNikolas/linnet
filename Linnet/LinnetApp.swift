import SwiftUI
import LinnetLibrary

@main
struct LinnetApp: App {
    @State private var playerViewModel = PlayerViewModel()
    @State private var artworkService = ArtworkService()
    @State private var appDatabase: AppDatabase? = {
        try? AppDatabase(location: .saved())
    }()
    @AppStorage("acoustIDAPIKey") private var acoustIDKey = ""
    @AppStorage("fanartTVAPIKey") private var fanartTVKey = ""
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 2

    init() {
        UserDefaults.standard.register(defaults: ["fontSizeOffset": 2.0])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(fontSizeOffset)
                .environment(playerViewModel)
                .environment(artworkService)
                .environment(\.appDatabase, appDatabase)
                .onAppear {
                    if let db = appDatabase {
                        playerViewModel.setAppDatabase(db)
                    }
                }
                .onChange(of: fanartTVKey, initial: true) { _, newValue in
                    artworkService.fanartTVAPIKey = newValue
                }
                .onChange(of: acoustIDKey, initial: true) { _, newValue in
                    artworkService.acoustIDAPIKey = newValue
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f")
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    playerViewModel.togglePlayPause()
                }
                .keyboardShortcut(" ", modifiers: [])

                Button("Next Track") {
                    playerViewModel.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Track") {
                    playerViewModel.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("Volume Up") {
                    playerViewModel.volume = min(playerViewModel.volume + 0.1, 1.0)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Volume Down") {
                    playerViewModel.volume = max(playerViewModel.volume - 0.1, 0.0)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Button("Shuffle") {
                    playerViewModel.queue.shuffle()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(\.appDatabase, appDatabase)
        }
    }
}
