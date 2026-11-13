import AppKit
import Foundation
import SwiftData
import TextsammlerKit
import UniformTypeIdentifiers

/// One copied text or image.
@Model
final class Clip {
    var text: String
    /// The app the text was copied in, like "Vorschau".
    var source: String = ""
    var isPinned: Bool = false
    /// When it was copied last. Copying the same text again moves it to the top.
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()
    /// A copied image as PNG, like a screenshot. Text is empty then.
    @Attribute(.externalStorage) var imageData: Data?
    var thumbnail: Data?
    /// Fingerprint of the image, so the same image is stored once.
    var imageHash: String = ""
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0

    init(text: String, source: String = "") {
        self.text = text
        self.source = source
    }

    var isImage: Bool { imageHash != "" }

    /// One line for lists and menus.
    var title: String {
        isImage ? "Bild \(pixelWidth) × \(pixelHeight)" : ClipText.title(text)
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case all, pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Verlauf"
        case .pinned: "Angeheftet"
        }
    }

    var symbol: String {
        switch self {
        case .all: "clock"
        case .pinned: "pin"
        }
    }
}

/// What goes between the entries when several are joined.
enum JoinSeparator: String, CaseIterable, Identifiable {
    case space, line, paragraph, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .space: "Leerzeichen"
        case .line: "Zeilenumbruch"
        case .paragraph: "Leerzeile"
        case .none: "Nichts"
        }
    }

    var string: String {
        switch self {
        case .space: " "
        case .line: "\n"
        case .paragraph: "\n\n"
        case .none: ""
        }
    }
}

/// App-wide state that menus, toolbars, and views share. Also watches the clipboard.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarItem? = .all
    var selection: Set<PersistentIdentifier> = []
    var confirmClear = false
    /// True for a moment after a copy, so the button can say "Kopiert".
    var justCopied = false

    var isPaused: Bool = UserDefaults.standard.bool(forKey: "capturePaused") {
        didSet { persist(isPaused, "capturePaused") }
    }
    var separator: JoinSeparator = JoinSeparator(rawValue: UserDefaults.standard.string(forKey: "joinSeparator") ?? "") ?? .paragraph {
        didSet { persist(separator.rawValue, "joinSeparator") }
    }
    /// Repair PDF line breaks and hyphenation in what gets copied out.
    var unwrap: Bool = UserDefaults.standard.object(forKey: "unwrapLines") as? Bool ?? true {
        didSet { persist(unwrap, "unwrapLines") }
    }
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { persist(settingsTab.rawValue, "settings.tab") }
    }

    @ObservationIgnored private var lastChange = NSPasteboard.general.changeCount
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var screenshotQuery: NSMetadataQuery?
    @ObservationIgnored private let launchedAt = Date.now
    /// True when macOS refused to read a screenshot file. Settings explains the fix.
    var screenshotFolderBlocked = false

    init(container: ModelContainer) {
        self.container = container
        startMonitoring()
        startScreenshotWatch()
    }

    private func persist(_ value: Any, _ key: String) {
        if !Store.isOverridden { UserDefaults.standard.set(value, forKey: key) }
    }

    // MARK: Clipboard

    /// Looks at the clipboard a few times a second. Test and snapshot runs never watch it.
    private func startMonitoring() {
        guard monitor == nil, !Store.isOverridden else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                self?.poll()
            }
        }
    }

    /// Asks Spotlight for new screenshot files, wherever macOS saves them
    /// (Desktop by default). Test and snapshot runs never watch.
    private func startScreenshotWatch() {
        guard screenshotQuery == nil, !Store.isOverridden else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated { self?.importScreenshots(paths) }
        }
        query.start()
        screenshotQuery = query
    }

    /// Adds screenshot files to the history. The files stay where they are.
    func importScreenshots(_ paths: [String]) {
        let wanted = UserDefaults.standard.object(forKey: "captureScreenshotFiles") as? Bool ?? true
        guard wanted, !isPaused else { return }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { continue }
            // Only screenshots taken while the app runs, never old ones Spotlight reports late.
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
            guard created > launchedAt.addingTimeInterval(-5) else { continue }
            guard let data = try? Data(contentsOf: url) else {
                screenshotFolderBlocked = true
                continue
            }
            screenshotFolderBlocked = false
            let png = url.pathExtension.lowercased() == "png" ? data : NSImage(data: data).flatMap(ImageTools.png(from:))
            if let png { captureImage(png, source: "Bildschirmfoto") }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard !isPaused else { return }
        // Password managers mark what they copy. Those never enter the history.
        let hidden: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        guard !(pasteboard.types ?? []).contains(where: { hidden.contains($0.rawValue) }) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        // Text wins: apps like Excel put a picture of the text beside it.
        if let text = pasteboard.string(forType: .string), capture(text, source: source) != nil { return }
        let wantsImages = UserDefaults.standard.object(forKey: "captureImages") as? Bool ?? true
        if wantsImages, let png = ImageTools.png(from: pasteboard) {
            captureImage(png, source: source.isEmpty ? "Bildschirmfoto" : source)
        }
    }

    /// Adds a copied image (PNG data) to the history. The same image again moves to the top.
    @discardableResult
    func captureImage(_ png: Data, source: String = "") -> Clip? {
        guard let size = ImageTools.pixelSize(png) else { return nil }
        let context = container.mainContext
        let hash = ImageTools.hash(png)
        var same = FetchDescriptor<Clip>(predicate: #Predicate { $0.imageHash == hash })
        same.fetchLimit = 1
        if let existing = try? context.fetch(same).first {
            existing.createdAt = .now
            try? context.save()
            return existing
        }
        let clip = Clip(text: "", source: source)
        clip.imageData = png
        clip.thumbnail = ImageTools.thumbnail(png)
        clip.imageHash = hash
        clip.pixelWidth = size.width
        clip.pixelHeight = size.height
        context.insert(clip)
        trimHistory()
        try? context.save()
        return clip
    }

    /// Adds a copied text to the history. The same text again moves to the top.
    @discardableResult
    func capture(_ text: String, source: String = "") -> Clip? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let context = container.mainContext
        var same = FetchDescriptor<Clip>(predicate: #Predicate { $0.text == text })
        same.fetchLimit = 1
        if let existing = try? context.fetch(same).first {
            existing.createdAt = .now
            if !source.isEmpty { existing.source = source }
            try? context.save()
            return existing
        }
        let clip = Clip(text: text, source: source)
        context.insert(clip)
        trimHistory()
        try? context.save()
        return clip
    }

    /// Keeps the newest entries up to the limit from Settings. Pinned entries always stay.
    func trimHistory() {
        let stored = UserDefaults.standard.integer(forKey: "historyLimit")
        let limit = stored > 0 ? stored : 200
        // Counted in memory: a fetch offset ignores entries that are not saved yet.
        let unpinned = FetchDescriptor<Clip>(predicate: #Predicate { !$0.isPinned }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        for clip in ((try? container.mainContext.fetch(unpinned)) ?? []).dropFirst(limit) { container.mainContext.delete(clip) }
    }

    // MARK: Actions on entries

    /// The entries with these ids, oldest first: the order they were copied in.
    func clips(_ ids: Set<PersistentIdentifier>) -> [Clip] {
        let all = (try? container.mainContext.fetch(FetchDescriptor<Clip>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { ids.contains($0.id) }
    }

    /// The text that leaves the app for these entries: joined, and repaired if wanted.
    func output(_ clips: [Clip]) -> String {
        ClipText.join(clips.filter { !$0.isImage }.map(\.text), separator: separator.string, unwrap: unwrap)
    }

    func copy(_ ids: Set<PersistentIdentifier>) {
        let chosen = clips(ids)
        let text = output(chosen)
        let images = chosen.compactMap { $0.imageData.flatMap(NSImage.init(data:)) }
        guard !text.isEmpty || !images.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if images.isEmpty {
            pasteboard.setString(text, forType: .string)
        } else {
            // Images go out as images; joined text rides along as its own item.
            pasteboard.writeObjects((text.isEmpty ? [] : [text as NSString]) + images)
        }
        // The app's own copy is not a new entry.
        lastChange = pasteboard.changeCount
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }

    /// Stores the joined text as one new entry and selects it.
    func saveJoined(_ ids: Set<PersistentIdentifier>) {
        let parts = clips(ids).filter { !$0.isImage }
        guard parts.count > 1, let clip = capture(output(parts), source: "Verknüpft") else { return }
        selection = [clip.id]
    }

    func togglePin(_ ids: Set<PersistentIdentifier>) {
        let chosen = clips(ids)
        let pin = !chosen.allSatisfy(\.isPinned)
        for clip in chosen { clip.isPinned = pin }
        try? container.mainContext.save()
    }

    func delete(_ ids: Set<PersistentIdentifier>) {
        for clip in clips(ids) { container.mainContext.delete(clip) }
        selection.subtract(ids)
        try? container.mainContext.save()
    }

    /// Removes everything that is not pinned.
    func clearHistory() {
        try? container.mainContext.delete(model: Clip.self, where: #Predicate { !$0.isPinned })
        try? container.mainContext.save()
        selection = []
    }
}
