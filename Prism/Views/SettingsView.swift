import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            EngineSettingsView()
                .tabItem { Label("Categorization", systemImage: "wand.and.stars") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}

private struct AccountSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Spotify App") {
                TextField("Client ID", text: $model.clientIDDraft)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Redirect URI") {
                    Text(SpotifyAuth.shared.redirectURI)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Save Client ID") {
                    model.saveClientID()
                }
            }
            Section("Connection") {
                if let profile = model.library.profile {
                    LabeledContent("Signed in as", value: profile.displayName)
                }
                LabeledContent(
                    "Status",
                    value: SpotifyAuth.shared.isAuthorized ? "Connected" : "Not connected"
                )
                Button("Disconnect Spotify", role: .destructive) {
                    model.signOut()
                }
                .disabled(!SpotifyAuth.shared.isAuthorized)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EngineSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Categorization engine") {
                Picker("Engine", selection: $model.engine) {
                    ForEach(AppModel.Engine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Re-categorize Library") {
                    Task { await model.categorize() }
                }
                .disabled(model.isWorking || !model.hasLibrary)
            }
        }
        .formStyle(.grouped)
    }

    private var description: String {
        switch model.engine {
        case .appleIntelligence:
            return "Uses the on-device Apple Intelligence model to group genres into smart categories. Runs fully offline — nothing leaves your Mac. Prism falls back to genre rules automatically if the model is unavailable."
        case .ruleBased:
            return "Sorts tracks with a fixed set of genre keyword rules. Instant and dependency-free, with less nuance than the on-device model."
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            PrismMark(size: 66)
            Text("Prism")
                .font(.title2.weight(.bold))
            Text("Version \(appVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Pull your Spotify library and split it into a spectrum of categories, sorted on-device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Link("View on GitHub", destination: URL(string: "https://github.com/MotionPeak/Prism")!)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
