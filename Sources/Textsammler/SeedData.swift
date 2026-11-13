import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with realistic items (short and long titles, starred and not).
/// Replace these with your app's own types. Seed only what a person can
/// create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Clip>())) ?? 0) == 0 else { return }
        let samples: [(String, String, Bool)] = [
            ("Die Lieferung erfolgt frei Haus ab einem Netto-\nwarenwert von 250,00 EUR. Für Bestellungen unter\ndiesem Wert berechnen wir eine Versandkosten-\npauschale von 9,90 EUR.", "Vorschau", false),
            ("Preise gültig ab 01.01.2027. Alle Preise verstehen\nsich in Euro zuzüglich der gesetzlichen Mehrwert-\nsteuer.", "Vorschau", false),
            ("Artikelnummer 4711-0815", "Vorschau", true),
            ("EAN 4006381333931", "Vorschau", false),
            ("Zahlungsziel: 30 Tage netto, 14 Tage 2 % Skonto", "Vorschau", true),
            ("SELECT ArtikelNr, Bezeichnung, EAN FROM Artikel WHERE Lieferant = 70012", "Visual Studio Code", false),
            ("https://example.com/katalog/preisliste-2027.pdf", "Safari", false),
            ("Sehr geehrte Damen und Herren,\nanbei erhalten Sie die aktualisierte Preisliste.", "Mail", false),
        ]
        for (index, sample) in samples.enumerated() {
            let clip = Clip(text: sample.0, source: sample.1)
            clip.isPinned = sample.2
            clip.createdAt = Date.now.addingTimeInterval(Double(-index) * 1_800)
            context.insert(clip)
        }
        try? context.save()
        // One screenshot, between the newest texts.
        model.captureImage(ImageTools.sample(), source: "Bildschirmfoto")?.createdAt = Date.now.addingTimeInterval(-900)
        try? context.save()
    }
}
