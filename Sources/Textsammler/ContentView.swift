import SwiftData
import SwiftUI
import TextsammlerKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } content: {
            ClipList(page: model.sidebar ?? .all)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ClipDetail()
        }
        .onChange(of: model.sidebar) { model.selection = [] }
        .confirmationDialog("Verlauf leeren?", isPresented: $model.confirmClear) {
            Button("Verlauf leeren", role: .destructive) { model.clearHistory() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Einträge außer den angehefteten werden gelöscht.")
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    }
}

struct ClipList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]
    @State private var search = ""
    let page: SidebarItem

    private var visible: [Clip] {
        clips.filter { clip in
            (page == .all || clip.isPinned)
                && (search.isEmpty || clip.text.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selection) { clip in
            ClipRow(clip: clip)
                .tag(clip.id)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            if !ids.isEmpty {
                Button(ids.count > 1 ? "Verknüpft kopieren" : "Kopieren", systemImage: "doc.on.doc") { model.copy(ids) }
                if ids.count > 1 {
                    Button("Als neuen Eintrag sichern", systemImage: "plus.square.on.square") { model.saveJoined(ids) }
                }
                Button("Anheften oder lösen", systemImage: "pin") { model.togglePin(ids) }
                Divider()
                Button("Löschen", systemImage: "trash", role: .destructive) { model.delete(ids) }
            }
        } primaryAction: { ids in
            model.copy(ids)
        }
        .searchable(text: $search, prompt: "Verlauf durchsuchen")
        .overlay {
            if visible.isEmpty {
                if !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if page == .pinned {
                    ContentUnavailableView(
                        "Nichts angeheftet",
                        systemImage: "pin",
                        description: Text("Angeheftete Einträge bleiben, auch wenn der Verlauf geleert wird.")
                    )
                } else {
                    ContentUnavailableView(
                        "Noch nichts kopiert",
                        systemImage: "doc.on.clipboard",
                        description: Text("Kopiere Text in einer beliebigen App. Er erscheint hier von selbst.")
                    )
                }
            }
        }
        .navigationTitle(page.title)
        .navigationSubtitle(model.isPaused ? "Erfassung pausiert" : "\(visible.count) Einträge")
        .toolbar {
            ToolbarItem {
                Button(model.isPaused ? "Erfassung fortsetzen" : "Erfassung pausieren",
                       systemImage: model.isPaused ? "play.fill" : "pause.fill") { model.isPaused.toggle() }
                    .help(model.isPaused ? "Kopierte Texte wieder sammeln" : "Kopierte Texte vorübergehend nicht sammeln")
            }
        }
    }
}

struct ClipRow: View {
    let clip: Clip

    var body: some View {
        HStack(spacing: Space.md) {
            if let data = clip.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 44)
                    .clipShape(.rect(cornerRadius: Space.xs))
                    .accessibilityHidden(true)
            }
            rowText
        }
        .padding(.vertical, Space.xs)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(clip.title)
                .lineLimit(2)
            HStack(spacing: Space.xs) {
                if clip.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Angeheftet")
                }
                if !clip.source.isEmpty { Text(clip.source + " ·") }
                Text(clip.createdAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Shows what would be copied: one entry, or several joined in the order they were copied.
struct ClipDetail: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Clip.createdAt) private var clips: [Clip]

    private var selected: [Clip] { clips.filter { model.selection.contains($0.id) } }

    var body: some View {
        @Bindable var model = model
        let selected = selected
        let text = model.output(selected)
        let images = selected.filter(\.isImage)
        Group {
            if selected.isEmpty {
                ContentUnavailableView(
                    "Kein Eintrag ausgewählt",
                    systemImage: "text.badge.plus",
                    description: Text("Wähle einen Eintrag, um ihn zu kopieren. Mit Command-Klick wählst du mehrere und verknüpfst sie zu einem Text.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            if !text.isEmpty {
                                Text(text)
                                    .textSelection(.enabled)
                            }
                            ForEach(images) { clip in
                                if let data = clip.imageData, let image = NSImage(data: data) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: image.size.width)
                                        .clipShape(.rect(cornerRadius: Space.xs))
                                        .accessibilityLabel(clip.title)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.margin)
                    }
                    Divider()
                    HStack(spacing: Space.lg) {
                        if !text.isEmpty {
                            Toggle("Zeilenumbrüche bereinigen", isOn: $model.unwrap)
                                .toggleStyle(.checkbox)
                                .fixedSize()
                                .help("Verbindet Zeilen eines Absatzes und am Zeilenende getrennte Wörter")
                        }
                        if selected.count - images.count > 1 {
                            Picker("Trennen mit", selection: $model.separator) {
                                ForEach(JoinSeparator.allCases) { Text($0.title).tag($0) }
                            }
                            .fixedSize()
                        }
                        Spacer()
                        Text(summary(selected, images: images, characters: text.count))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.vertical, Space.md)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Anheften", systemImage: selected.allSatisfy(\.isPinned) && !selected.isEmpty ? "pin.slash" : "pin") {
                    model.togglePin(model.selection)
                }
                .help("Anheften oder lösen (Command-D)")
                Button("Löschen", systemImage: "trash") { model.delete(model.selection) }
                    .help("Löschen (Command-Rückschritt)")
            }
            if selected.count - images.count > 1 {
                ToolbarItem {
                    Button("Als Eintrag sichern", systemImage: "plus.square.on.square") { model.saveJoined(model.selection) }
                        .help("Den verknüpften Text als neuen Eintrag sichern (Command-S)")
                }
            }
            ToolbarItem {
                Button(model.justCopied ? "Kopiert" : (selected.count - images.count > 1 ? "Verknüpft kopieren" : "Kopieren"),
                       systemImage: model.justCopied ? "checkmark" : "doc.on.doc") { model.copy(model.selection) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .help("In die Zwischenablage kopieren (Umschalt-Command-C)")
            }
        }
        .disabled(selected.isEmpty)
    }
}

extension ClipDetail {
    /// "2 Einträge · 270 Zeichen", "1200 × 800 Pixel", or both kinds counted.
    fileprivate func summary(_ selected: [Clip], images: [Clip], characters: Int) -> String {
        if selected.count == 1, let image = images.first { return "\(image.pixelWidth) × \(image.pixelHeight) Pixel" }
        if images.isEmpty { return selected.count > 1 ? "\(selected.count) Einträge · \(characters) Zeichen" : "\(characters) Zeichen" }
        let pictures = images.count == 1 ? "1 Bild" : "\(images.count) Bilder"
        return characters > 0 ? "\(pictures) · \(characters) Zeichen" : pictures
    }
}

/// The menu bar item: the newest entries, one click copies.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]

    var body: some View {
        @Bindable var model = model
        if clips.isEmpty {
            Text("Noch nichts kopiert")
        }
        ForEach(clips.prefix(10)) { clip in
            Button(clip.isImage ? clip.title : ClipText.title(clip.text, limit: 60)) { model.copy([clip.id]) }
        }
        Divider()
        Button("Textsammler öffnen") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Toggle("Erfassung pausieren", isOn: $model.isPaused)
        Divider()
        Button("Textsammler beenden") { NSApp.terminate(nil) }
    }
}
