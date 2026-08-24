#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "One to three short, neutral food-diary fun facts")
private struct FoundationFactResponse {
    @Guide(
        description: "Facts grounded only in the verified statement, each under 220 characters",
        .count(1...3)
    )
    var facts: [String]
}

@available(iOS 26.0, macOS 26.0, *)
func foundationModelFactAvailability(locale: Locale) -> OnDeviceFactAvailability {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        return model.supportsLocale(locale) ? .available : .unsupportedLocale
    case let .unavailable(reason):
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
actor FoundationModelFactGenerator: FactGenerating {
    private let locale: Locale
    private let model: SystemLanguageModel

    init(locale: Locale, model: SystemLanguageModel = .default) {
        self.locale = locale
        self.model = model
    }

    func generate(totals: FactTotals, firstName: String?) async throws -> GeneratedFacts {
        switch model.availability {
        case .available:
            guard model.supportsLocale(locale) else {
                throw FactGenerationError.unsupportedLocale
            }
        case .unavailable:
            throw FactGenerationError.modelUnavailable
        }

        let prompt = FactPrompt.request(totals: totals, firstName: firstName)
        let session = LanguageModelSession(
            model: model,
            instructions: FactPrompt.systemInstructions
        )
        session.prewarm()

        let response: LanguageModelSession.Response<FoundationFactResponse>
        do {
            response = try await session.respond(
                to: prompt,
                generating: FoundationFactResponse.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 300
                )
            )
        } catch {
            throw FactGenerationError.generationFailed
        }

        return try FactPrompt.validated(
            facts: response.content.facts,
            debug: "Generated on device from Wastly's deterministic fact totals."
        )
    }
}
#endif
