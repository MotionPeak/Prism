import Observation
import SwiftUI
import WebKit

// Drives in-app playback via the Spotify Web Playback SDK, which runs as
// JavaScript inside a hidden WKWebView. Requires a Spotify Premium account.
@MainActor
@Observable
final class WebPlaybackController {
    var isReady = false
    var isActive = false
    var isPaused = true
    var trackName = ""
    var artistName = ""
    var currentURI: String?
    var artURL: String?
    var positionMs = 0
    var durationMs = 0
    var statusMessage = "Starting the web player…"
    var hasError = false

    private var deviceID: String?
    private var webView: WKWebView?
    private var ticker: Timer?

    init() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // Advances the displayed position between SDK state events.
    private func tick() {
        guard isActive, !isPaused, durationMs > 0 else { return }
        positionMs = min(positionMs + 500, durationMs)
    }

    // Lazily builds the single WKWebView that hosts the SDK.
    func webPlayerView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let proxy = ScriptMessageProxy { [weak self] message in
            self?.handle(message)
        }
        configuration.userContentController.add(proxy, name: "prism")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://prism.local"))
        self.webView = webView
        return webView
    }

    // MARK: - Controls

    func play(track: LibraryTrack, in queue: [LibraryTrack]) async {
        guard let deviceID else {
            statusMessage = "The web player is still starting up — try again in a moment."
            return
        }
        // Send a window of the surrounding tracks as the queue so that
        // Next / Previous have somewhere to go.
        let index = queue.firstIndex { $0.id == track.id } ?? 0
        let start = max(0, index - 30)
        let window = Array(queue[start..<min(queue.count, start + 100)])
        let uris = window.map(\.uri)
        do {
            try await SpotifyClient.shared.startPlayback(
                deviceID: deviceID,
                uris: uris.isEmpty ? [track.uri] : uris,
                offsetPosition: uris.isEmpty ? 0 : index - start
            )
            statusMessage = ""
            hasError = false
        } catch {
            statusMessage = error.localizedDescription
            hasError = true
        }
    }

    func togglePlay() { evaluate("prismToggle()") }
    func next() { evaluate("prismNext()") }
    func previous() { evaluate("prismPrevious()") }

    func seek(toMs milliseconds: Int) {
        positionMs = max(0, min(milliseconds, durationMs))
        evaluate("prismSeek(\(positionMs))")
    }

    private func evaluate(_ javaScript: String) {
        webView?.evaluateJavaScript(javaScript, completionHandler: nil)
    }

    // MARK: - Messages from the SDK

    private func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "needToken":
            Task { await deliverToken() }
        case "ready":
            deviceID = message["deviceId"] as? String
            isReady = true
            statusMessage = ""
            hasError = false
        case "notReady":
            isReady = false
        case "state":
            let active = message["active"] as? Bool ?? false
            isActive = active
            guard active else { currentURI = nil; return }
            isPaused = message["paused"] as? Bool ?? true
            trackName = message["name"] as? String ?? ""
            artistName = message["artist"] as? String ?? ""
            currentURI = message["uri"] as? String
            let art = message["art"] as? String ?? ""
            artURL = art.isEmpty ? nil : art
            positionMs = message["position"] as? Int ?? 0
            durationMs = message["duration"] as? Int ?? 0
        case "error":
            statusMessage = message["message"] as? String ?? "Playback error."
            hasError = true
        default:
            break
        }
    }

    private func deliverToken() async {
        do {
            let token = try await SpotifyAuth.shared.validAccessToken()
            evaluate("prismDeliverToken('\(token)')")
        } catch {
            statusMessage = "Could not get a Spotify token for playback."
        }
    }

    // MARK: - SDK host page

    private static let html = """
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Prism Player</title></head>
    <body>
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
    <script>
    function send(message) { window.webkit.messageHandlers.prism.postMessage(message); }

    function prismDeliverToken(token) {
      if (window.__prismTokenCb) { window.__prismTokenCb(token); window.__prismTokenCb = null; }
    }
    function prismToggle() { if (window.__prismPlayer) window.__prismPlayer.togglePlay(); }
    function prismNext() { if (window.__prismPlayer) window.__prismPlayer.nextTrack(); }
    function prismPrevious() { if (window.__prismPlayer) window.__prismPlayer.previousTrack(); }
    function prismSeek(ms) { if (window.__prismPlayer) window.__prismPlayer.seek(ms); }

    window.onSpotifyWebPlaybackSDKReady = () => {
      const player = new Spotify.Player({
        name: 'Prism',
        getOAuthToken: cb => { window.__prismTokenCb = cb; send({ type: 'needToken' }); },
        volume: 0.8
      });
      window.__prismPlayer = player;

      player.addListener('ready', e => send({ type: 'ready', deviceId: e.device_id }));
      player.addListener('not_ready', () => send({ type: 'notReady' }));
      player.addListener('player_state_changed', s => {
        if (!s) { send({ type: 'state', active: false }); return; }
        const t = s.track_window.current_track;
        send({
          type: 'state', active: true, paused: s.paused,
          position: s.position, duration: s.duration,
          uri: t.uri,
          name: t.name,
          artist: t.artists.map(a => a.name).join(', '),
          art: (t.album.images[0] || {}).url || ''
        });
      });
      player.addListener('initialization_error', e => send({ type: 'error', message: e.message }));
      player.addListener('authentication_error', e => send({ type: 'error', message: 'Spotify sign-in failed for playback. Reconnect in Settings.' }));
      player.addListener('account_error', () => send({ type: 'error', message: 'In-app playback needs Spotify Premium.' }));
      player.addListener('playback_error', e => send({ type: 'error', message: e.message }));
      player.connect();
    };
    </script>
    </body>
    </html>
    """
}

// Bridges WKScriptMessageHandler (which must be an NSObject) to a closure.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private let onMessage: ([String: Any]) -> Void

    init(_ onMessage: @escaping ([String: Any]) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if let body = message.body as? [String: Any] {
            onMessage(body)
        }
    }
}

// Embeds the SDK's WKWebView in the SwiftUI hierarchy (kept tiny and hidden;
// it only needs to exist for audio playback to run).
struct WebPlaybackHostView: NSViewRepresentable {
    @Environment(WebPlaybackController.self) private var controller

    func makeNSView(context: Context) -> WKWebView {
        controller.webPlayerView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
