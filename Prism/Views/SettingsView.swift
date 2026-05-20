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
        .frame(width: 520, height: 480)
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

            Section("Permissions") {
                permissionsContent
                Button("Reconnect Spotify") {
                    Task { await model.reconnect() }
                }
                .disabled(model.isWorking)
                .help("Sign out and authorize again to refresh the permissions Spotify grants")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var permissionsContent: some View {
        if !SpotifyAuth.shared.isAuthorized {
            Text("Connect Spotify to see which permissions it granted.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if SpotifyAuth.shared.grantedScopes.isEmpty {
            Text("Reconnect to check which permissions Spotify granted to Prism.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            let missing = SpotifyAuth.shared.missingWriteScopes
            if missing.isEmpty {
                Label("Playlist and library editing is granted", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Write permissions were not granted", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Spotify did not grant: \(missing.joined(separator: ", ")). Creating playlists and editing your library will fail until this is resolved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Granted scopes: \(SpotifyAuth.shared.grantedScopes)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct EngineSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var ollamaURLDraft = ""

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

            if model.engine == .ollama {
                Section("Ollama") {
                    if model.availableOllamaModels.isEmpty {
                        Text("No models found. Make sure Ollama is installed and running, then pull a model — for example:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("ollama pull qwen2.5:7b")
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Picker("Model", selection: $model.ollamaModel) {
                            ForEach(model.availableOllamaModels, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    HStack {
                        TextField("Server URL", text: $ollamaURLDraft, prompt: Text(OllamaClient.defaultBaseURL))
                            .font(.system(.callout, design: .monospaced))
                        Button("Refresh") {
                            OllamaClient.shared.setBaseURL(ollamaURLDraft)
                            Task { await model.refreshOllamaModels() }
                        }
                    }
                }
            }

            Section {
                Text(engineDescription)
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
        .task {
            ollamaURLDraft = OllamaClient.shared.baseURL.absoluteString
            await model.refreshOllamaModels()
        }
    }

    private var engineDescription: String {
        switch model.engine {
        case .appleIntelligence:
            return "Classifies your library by artist using the built-in Apple Intelligence model. Free, fully offline, no setup — but it is a small model, so it knows mainstream artists best."
        case .ollama:
            return "Classifies your library by artist using a local model served by Ollama. Install Ollama, pull a model such as qwen2.5:7b or llama3.1:8b, then pick it above. Everything runs on your Mac."
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
