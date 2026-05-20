import Foundation

// Talks to a local Ollama server (https://ollama.com) over HTTP.
// Used as one of Prism's categorization backends — fully local, free.
final class OllamaClient {
    static let shared = OllamaClient()
    private init() {}

    static let defaultBaseURL = "http://localhost:11434"
    private let baseURLKey = "ollamaBaseURL"

    var baseURL: URL {
        if let stored = UserDefaults.standard.string(forKey: baseURLKey),
           !stored.isEmpty,
           let url = URL(string: stored) {
            return url
        }
        return URL(string: Self.defaultBaseURL)!
    }

    func setBaseURL(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? Self.defaultBaseURL : trimmed, forKey: baseURLKey)
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    // Names of every model currently installed in Ollama.
    func listModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 10

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw CategorizerError.ollamaUnreachable("Ollama returned an unexpected response.")
            }
            data = responseData
        } catch let error as CategorizerError {
            throw error
        } catch {
            throw CategorizerError.ollamaUnreachable("Couldn't connect at \(baseURL.absoluteString).")
        }

        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        return tags.models.map(\.name).sorted()
    }

    // Runs a single non-streaming completion, constrained to JSON output.
    func generate(model: String, prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 240
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": ["temperature": 0],
        ])

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CategorizerError.ollamaUnreachable("No response from Ollama.")
            }
            guard http.statusCode == 200 else {
                let detail = String(data: responseData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw CategorizerError.ollamaUnreachable(String(detail.prefix(200)))
            }
            data = responseData
        } catch let error as CategorizerError {
            throw error
        } catch {
            throw CategorizerError.ollamaUnreachable("Couldn't connect at \(baseURL.absoluteString).")
        }

        return try JSONDecoder().decode(GenerateResponse.self, from: data).response
    }
}
