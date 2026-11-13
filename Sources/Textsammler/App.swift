import AppKit
import SwiftData
import SwiftUI

// Textsammler
//   Textsammler                      the app
//   APP_STORE=<file> Textsammler     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> Textsammler   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Textsammler           fill an empty /tmp store with sample items (tools/snap.sh)
//   Textsammler --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Textsammler      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Textsammler           draw the 8 pt grid and the layout probes over the window

@main
struct TextsammlerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("Textsammler", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(model.selection.count > 1 ? "Verknüpft kopieren" : "Eintrag kopieren") { model.copy(model.selection) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.selection.isEmpty)
                Button("Als neuen Eintrag sichern") { model.saveJoined(model.selection) }
                    .keyboardShortcut("s")
                    .disabled(model.selection.count < 2)
                Button("Anheften oder lösen") { model.togglePin(model.selection) }
                    .keyboardShortcut("d")
                    .disabled(model.selection.isEmpty)
                Button("Eintrag löschen") { model.delete(model.selection) }
                    .keyboardShortcut(.delete)
                    .disabled(model.selection.isEmpty)
                Divider()
                Toggle("Erfassung pausieren", isOn: Binding(get: { model.isPaused }, set: { model.isPaused = $0 }))
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Verlauf leeren …") { model.confirmClear = true }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Textsammler", systemImage: "doc.on.clipboard") {
            MenuBarContent()
                .environment(model)
                .modelContainer(model.container)
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Closing the window keeps the app collecting. The menu bar item and the Dock bring it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/Textsammler/Textsammler.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "Textsammler", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "Textsammler.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Clip.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
