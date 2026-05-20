import Foundation
import Network

// A one-shot HTTP listener on 127.0.0.1 used to catch the Spotify OAuth redirect.
// Spotify permits loopback redirect URIs, which avoids registering a custom URL scheme.
final class LoopbackServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.motionpeak.prism.loopback")
    private var onRequest: ((URLComponents) -> Void)?

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start(onRequest: @escaping (URLComponents) -> Void) throws {
        self.onRequest = onRequest
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onRequest = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let requestLine = self.firstRequestLine(buffer) {
                self.reply(on: connection)
                self.parse(requestLine)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func firstRequestLine(_ buffer: Data) -> String? {
        guard let text = String(data: buffer, encoding: .utf8),
              let lineEnd = text.range(of: "\r\n")
        else { return nil }
        return String(text[text.startIndex..<lineEnd.lowerBound])
    }

    private func parse(_ requestLine: String) {
        // Expected: "GET /callback?code=...&state=... HTTP/1.1"
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])")
        else { return }
        onRequest?(components)
    }

    private func reply(on connection: NWConnection) {
        let body = Data(Self.successPage.utf8)
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: text/html; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let successPage = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Prism</title>
      <style>
        html, body { height: 100%; margin: 0; }
        body {
          display: flex; align-items: center; justify-content: center;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          background: linear-gradient(160deg, #1a1530 0%, #0b0a14 100%);
          color: #f4f2ff;
        }
        .card { text-align: center; padding: 48px; }
        h1 { font-size: 22px; font-weight: 600; margin: 16px 0 6px; }
        p { color: #b9b4d6; font-size: 14px; margin: 0; }
        .dot {
          width: 56px; height: 56px; margin: 0 auto; border-radius: 16px;
          background: conic-gradient(from 210deg, #ff5b5b, #ffb14e, #ffe14e, #5bff8f, #4ec3ff, #b46bff, #ff5b5b);
        }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="dot"></div>
        <h1>Connected to Spotify</h1>
        <p>You can close this tab and return to Prism.</p>
      </div>
    </body>
    </html>
    """
}
