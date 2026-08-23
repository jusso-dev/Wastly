import Foundation
import Testing
@testable import WastlyKit

func response(_ pack: CatalogPack, etag: String? = nil) throws -> CatalogHTTPResponse {
    CatalogHTTPResponse(
        data: try JSONEncoder().encode(pack),
        statusCode: 200,
        etag: etag
    )
}

func queryValue(_ name: String, in request: URLRequest) -> String? {
    request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}

func assertCatalogRequests(_ requests: [URLRequest]) {
    #expect(requests.count == 2)
    #expect(queryValue("updatedSince", in: requests[0]) == "0")
    #expect(queryValue("pack", in: requests[0]) == "1")
    #expect(queryValue("pack", in: requests[1]) == "2")
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    #expect(requests.allSatisfy { request in
        let items = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }?.queryItems ?? []
        return Set(items.map(\.name)) == ["updatedSince", "pack"]
    })
}

actor FixtureCatalogHTTPClient: CatalogHTTPClient {
    private let responses: [CatalogHTTPResponse]
    private let failureAt: Int?
    private var requests: [URLRequest] = []

    init(responses: [CatalogHTTPResponse], failureAt: Int? = nil) {
        self.responses = responses
        self.failureAt = failureAt
    }

    func data(for request: URLRequest) async throws -> CatalogHTTPResponse {
        let index = requests.count
        requests.append(request)
        if failureAt == index { throw URLError(.networkConnectionLost) }
        guard responses.indices.contains(index) else { throw URLError(.resourceUnavailable) }
        return responses[index]
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

actor SuspendingCatalogHTTPClient: CatalogHTTPClient {
    private var started = false

    func data(for request: URLRequest) async throws -> CatalogHTTPResponse {
        started = true
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }

    func hasStarted() -> Bool {
        started
    }
}
