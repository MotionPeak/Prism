import Foundation

// Runs prompts on a local model served by Ollama.
struct OllamaRunner: LLMRunner {
    let model: String

    func preflight() async throws {
        guard !model.isEmpty else { throw CategorizerError.ollamaNoModel }
        let installed = try await OllamaClient.shared.listModels()
        guard installed.contains(model) else {
            throw CategorizerError.ollamaModelMissing(model)
        }
    }

    func complete(_ prompt: String) async throws -> String {
        try await OllamaClient.shared.generate(model: model, prompt: prompt)
    }
}
