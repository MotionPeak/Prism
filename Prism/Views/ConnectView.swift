import AppKit
import SwiftUI

struct ConnectView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.08, blue: 0.18), Color(red: 0.04, green: 0.03, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    if model.phase == .needsClientID {
                        ClientIDCard()
                    } else {
                        ConnectCard()
                    }
                    if let banner = model.banner, banner.kind == .error {
                        BannerCard(banner: banner) { model.dismissBanner() }
                            .frame(maxWidth: 520)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            PrismMark(size: 78)
            Text("Prism")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Pull your Spotify library and split it into a spectrum of categories — sorted on-device.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
    }
}

private struct ClientIDCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect your own Spotify app", systemImage: "key.fill")
                .font(.headline)

            Text("Prism uses your own free Spotify developer app, so your listening data only ever goes between your Mac and Spotify.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Open the Spotify Developer Dashboard and log in.")
                step(2, "Click Create app. Name it anything, like “Prism”.")
                step(3, "Under Redirect URIs, add this exact address:")
                Text(SpotifyAuth.shared.redirectURI)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                step(4, "Tick the Web API checkbox, save, then open the app's Settings.")
                step(5, "Copy the Client ID and paste it below.")
            }

            Button {
                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
            } label: {
                Label("Open Spotify Developer Dashboard", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.link)

            Divider()

            Text("Client ID")
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Paste your Spotify Client ID", text: $model.clientIDDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Save") {
                    model.saveClientID()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: 540)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(PrismTheme.spectrumColors[(number - 1) % PrismTheme.spectrumColors.count], in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ConnectCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Label("Client ID saved", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Now connect your Spotify account. Your browser will open so you can approve access — then Prism syncs automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await model.connect() }
            } label: {
                Group {
                    if model.isWorking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for Spotify…")
                        }
                    } else {
                        Text("Connect Spotify")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)

            Button("Use a different Client ID") {
                SpotifyAuth.shared.clientID = ""
                model.clientIDDraft = ""
                model.refreshPhase()
            }
            .buttonStyle(.link)
            .disabled(model.isWorking)
        }
        .padding(24)
        .frame(maxWidth: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
