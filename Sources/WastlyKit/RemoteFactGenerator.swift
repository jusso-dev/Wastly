import Foundation

public enum FactPrompt: Sendable {
    public static let version = "neutral-v1"
    public static let systemInstructions = """
    Write one to three short, neutral fun facts in Australian English from the supplied aggregates only.
    Use honest grams-to-object arithmetic and return that working in the debug field.
    Never use the phrases obesity, too much, or be better. Do not give health, weight, or parenting advice.
    Return JSON with facts as an array of strings and debug as a short string.
    """

    private static let forbiddenPhrases = ["obesity", "too much", "be better"]

    public static func accepts(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return forbiddenPhrases.allSatisfy { !lowercased.contains($0) }
    }
}

public struct GeneratedFacts: Equatable, Sendable {
    public var facts: [String]
    public var debug: String

    public var text: String {
        facts.joined(separator: "\n\n")
    }

    public init(facts: [String], debug: String) {
        self.facts = facts
        self.debug = debug
    }
}

public enum FactGenerationSource: Equatable, Sendable {
    case template
    case remote
}

public struct FactGenerationResult: Equatable, Sendable {
    public var text: String
    public var source: FactGenerationSource
    public var debug: String?

    public init(text: String, source: FactGenerationSource, debug: String? = nil) {
        self.text = text
        self.source = source
        self.debug = debug
    }
}

public protocol FactGenerating: Sendable {
    func generate(totals: FactTotals, firstName: String?) async throws -> GeneratedFacts
}

public enum FactService: Sendable {
    public static func generateOrFallback(
        totals: FactTotals,
        firstName: String?,
        using generator: (any FactGenerating)?
    ) async -> FactGenerationResult {
        let fallback = FactTemplates.fact(for: totals, firstName: firstName)
        guard totals.eatenGrams + totals.wastedGrams >= 1,
              let generator
        else {
            return FactGenerationResult(text: fallback, source: .template)
        }

        do {
            let generated = try await generator.generate(totals: totals, firstName: firstName)
            return FactGenerationResult(
                text: generated.text,
                source: .remote,
                debug: generated.debug
            )
        } catch {
            return FactGenerationResult(text: fallback, source: .template)
        }
    }
}

public enum FactGenerationError: Error, LocalizedError, Sendable {
    case invalidResponse
    case serviceUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The optional fact service returned an unreadable response."
        case .serviceUnavailable:
            "The optional fact service is unavailable."
        }
    }
}

struct FactHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
}

protocol FactHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> FactHTTPResponse
}

private struct URLSessionFactHTTPClient: FactHTTPClient {
    var session: URLSession

    func data(for request: URLRequest) async throws -> FactHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FactGenerationError.invalidResponse
        }
        return FactHTTPResponse(data: data, statusCode: http.statusCode)
    }
}

public actor RemoteFactGenerator: FactGenerating {
    private let endpoint: URL
    private let configuredHost: String
    private let apiKey: String?
    private let client: any FactHTTPClient

    public init(
        endpoint: URL,
        apiKey: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.configuredHost = endpoint.host ?? ""
        self.apiKey = apiKey
        self.client = URLSessionFactHTTPClient(session: urlSession)
    }

    init(
        endpoint: URL,
        apiKey: String? = nil,
        client: any FactHTTPClient
    ) {
        self.endpoint = endpoint
        self.configuredHost = endpoint.host ?? ""
        self.apiKey = apiKey
        self.client = client
    }

    public func generate(
        totals: FactTotals,
        firstName: String?
    ) async throws -> GeneratedFacts {
        let request = try FactRequestBuilder.make(
            url: endpoint,
            configuredHost: configuredHost,
            apiKey: apiKey,
            totals: totals,
            firstName: firstName
        )
        let response: FactHTTPResponse
        do {
            response = try await client.data(for: request)
        } catch {
            throw FactGenerationError.serviceUnavailable
        }
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(FactServiceResponse.self, from: response.data)
        else {
            throw FactGenerationError.invalidResponse
        }

        let facts = payload.facts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let debug = payload.debug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...3).contains(facts.count),
              facts.allSatisfy({ !$0.isEmpty && $0.count <= 280 && FactPrompt.accepts($0) }),
              !debug.isEmpty,
              debug.count <= 500,
              FactPrompt.accepts(debug)
        else {
            throw FactGenerationError.invalidResponse
        }
        return GeneratedFacts(facts: facts, debug: debug)
    }
}

private struct FactServiceResponse: Decodable, Sendable {
    var facts: [String]
    var debug: String
}
