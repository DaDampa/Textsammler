import AppKit
import SwiftData

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Textsammler-self.store ~/Applications/Textsammler.app/Contents/MacOS/Textsammler --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            func clips() -> [Clip] { (try? context.fetch(FetchDescriptor<Clip>())) ?? [] }

            let before = clips().count
            let first = model.capture("Erster Teil mit Zeilen-\numbruch", source: "Test")
            try? await Task.sleep(for: .milliseconds(20))
            let second = model.capture("zweiter Teil")
            check("copied text enters the history", clips().count == before + 2)
            check("empty text is ignored", model.capture("  \n ") == nil && clips().count == before + 2)
            model.capture("zweiter Teil")
            check("the same text again adds no duplicate", clips().count == before + 2)

            if let first, let second {
                let ids: Set = [first.id, second.id]
                model.unwrap = true
                model.separator = .space
                check("entries join in copy order, PDF breaks repaired",
                      model.output(model.clips(ids)) == "Erster Teil mit Zeilenumbruch zweiter Teil",
                      model.output(model.clips(ids)))
                model.saveJoined(ids)
                check("the joined text becomes a new, selected entry",
                      clips().count == before + 3 && model.selection.count == 1)
                model.togglePin(ids)
                check("pinning marks the entries", first.isPinned && second.isPinned)
                model.clearHistory()
                check("clearing keeps pinned entries", clips().count == 2)
                model.delete(ids)
                check("deleting removes the entries", clips().isEmpty)
            }

            let shot = ImageTools.sample(width: 320, height: 200)
            let image = model.captureImage(shot, source: "Test")
            check("a copied image enters the history with its size",
                  image?.isImage == true && (image?.pixelWidth ?? 0) > 0 && image?.thumbnail != nil)
            model.captureImage(shot)
            check("the same image again adds no duplicate", clips().count == 1)
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Textsammler-selftest.png")
            try? ImageTools.sample(width: 200, height: 100, hue: 0.3).write(to: file)
            model.importScreenshots([file.path, "/tmp/Textsammler-selftest.mov"])
            check("a saved screenshot file enters the history, other files do not", clips().count == 2)
            try? FileManager.default.removeItem(at: file)
            for clip in clips() where clip.id != image?.id { context.delete(clip) }
            if let image {
                check("images stay out of joined text", model.output([image]).isEmpty)
                model.delete([image.id])
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
