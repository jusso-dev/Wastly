import Foundation
import SwiftData

public struct CatalogPack: Codable, Sendable {
    public var version: Int
    public var etag: String?
    public var foods: [SeedFood]

    public init(version: Int, etag: String? = nil, foods: [SeedFood]) {
        self.version = version
        self.etag = etag
        self.foods = foods
    }
}

public actor CatalogSync {
    private let store: LocalFoodStore
    private let extraHosts: Set<String>
    private let session: URLSession

    public init(store: LocalFoodStore, extraHosts: Set<String> = [], session: URLSession = .shared) {
        self.store = store
        self.extraHosts = extraHosts
        self.session = session
    }

    /// Incremental pull. A failed chunk leaves the previous catalog version in place.
    public func pull(from url: URL, currentVersion: Int) async throws -> CatalogPack {
        guard PrivacyAllowlist.isAllowedCatalogURL(url, extraHosts: extraHosts) else {
            throw URLError(.badURL)
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "updatedSince", value: String(currentVersion)))
        components?.queryItems = items
        guard let requestURL = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: requestURL)
        request.setValue("Wastly/1.0 (https://github.com/jusso-dev/Wastly)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let pack = try JSONDecoder().decode(CatalogPack.self, from: data)
        await store.upsertCatalog(pack.foods, version: pack.version)
        return pack
    }
}
