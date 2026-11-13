import ServiceManagement
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Allgemein"
        case .appearance: "Darstellung"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("historyLimit") private var historyLimit = 200
    @AppStorage("captureImages") private var captureImages = true
    @AppStorage("captureScreenshotFiles") private var captureScreenshotFiles = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section {
            Picker("Einträge behalten", selection: $historyLimit) {
                ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
            }
            .onChange(of: historyLimit) { model.trimHistory() }
            Toggle("Kopierte Bilder sammeln", isOn: $captureImages)
            Toggle("Gesicherte Bildschirmfotos sammeln", isOn: $captureScreenshotFiles)
        } header: {
            Text("Verlauf")
        } footer: {
            Text(model.screenshotFolderBlocked
                 ? "Textsammler darf den Ordner mit den Bildschirmfotos nicht lesen. Erlaube den Zugriff in Systemeinstellungen > Datenschutz & Sicherheit > Dateien & Ordner."
                 : "Ältere Einträge werden gelöscht. Angeheftete Einträge bleiben immer. Bildschirmfotos erscheinen im Verlauf, sobald macOS die Datei gesichert hat. Die Datei bleibt an ihrem Ort.")
        }
        Section("Start") {
            Toggle("Beim Anmelden starten", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
        }
    }
}
