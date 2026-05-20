#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

// Runs prompts on the built-in Apple Intelligence model. Free, on-device, no setup.
struct AppleIntelligenceRunner: LLMRunner {
    func preflight() async throws {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw CategorizerError.appleIntelligenceUnavailable("\(reason)")
        @unknown default:
            throw CategorizerError.appleIntelligenceUnavailable("unknown reason")
        }
        #else
        throw CategorizerError.appleIntelligenceUnavailable("the Foundation Models framework is not available")
        #endif
    }

    func complete(_ prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        // A fresh session per call keeps each batch independent.
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw CategorizerError.appleIntelligenceUnavailable("the Foundation Models framework is not available")
        #endif
    }
}
