import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PlateMatchCandidate: Codable, Equatable, Identifiable, Sendable {
    public var providerID: String?
    public var name: String
    public var confidence: Double
    public var kilojoulesPer100g: Double?
    public var servingGrams: Double?

    public var id: String {
        providerID ?? name.lowercased()
    }

    public var foodHit: FoodHit {
        FoodHit(
            id: "plate:\(id)",
            name: name,
            kilojoulesPer100g: kilojoulesPer100g ?? 0,
            servingGrams: servingGrams,
            origin: .cloudPlate
        )
    }

    public init(
        providerID: String? = nil,
        name: String,
        confidence: Double,
        kilojoulesPer100g: Double? = nil,
        servingGrams: Double? = nil
    ) {
        self.providerID = providerID
        self.name = name
        self.confidence = confidence
        self.kilojoulesPer100g = kilojoulesPer100g
        self.servingGrams = servingGrams
    }

    enum CodingKeys: String, CodingKey {
        case providerID = "id"
        case name
        case confidence
        case kilojoulesPer100g
        case servingGrams
    }
}

public enum PlateMatchError: Error, LocalizedError, Sendable {
    case unreadableImage
    case invalidResponse
    case serviceUnavailable

    public var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "That plate photo couldn’t be prepared. Try another photo."
        case .invalidResponse:
            "The plate matcher returned an unreadable response."
        case .serviceUnavailable:
            "The plate matcher is unavailable. Search for the food instead."
        }
    }
}

public enum PlateImagePreparer: Sendable {
    /// Returns a center crop with orientation applied, no source metadata, and bounded JPEG bytes.
    public static func jpegCrop(
        from imageData: Data,
        maxPixelSize: Int = 768,
        compressionQuality: Double = 0.72
    ) -> Data? {
        guard maxPixelSize > 0,
              (0...1).contains(compressionQuality),
              let source = CGImageSourceCreateWithData(imageData as CFData, nil)
        else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else { return nil }

        let side = min(image.width, image.height)
        let cropRect = CGRect(
            x: CGFloat(image.width - side) / 2,
            y: CGFloat(image.height - side) / 2,
            width: CGFloat(side),
            height: CGFloat(side)
        )
        guard let crop = image.cropping(to: cropRect) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]
        CGImageDestinationAddImage(destination, crop, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

public enum PlateMatchRequestBuilder: Sendable {
    public static func make(
        url: URL,
        configuredHost: String,
        apiKey: String?,
        jpegCrop: Data
    ) throws -> URLRequest {
        guard PrivacyAllowlist.isAllowedPlateMatchURL(url, configuredHost: configuredHost) else {
            throw PrivacyError.disallowedDestination
        }
        let body = try PlateMatchRequest(jpegCrop: jpegCrop).encodedJSON()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Wastly/1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }
}

struct PlateHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
}

protocol PlateHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> PlateHTTPResponse
}

private struct URLSessionPlateHTTPClient: PlateHTTPClient {
    var session: URLSession

    func data(for request: URLRequest) async throws -> PlateHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlateMatchError.invalidResponse
        }
        return PlateHTTPResponse(data: data, statusCode: http.statusCode)
    }
}

public actor RemotePlateMatcher {
    private let endpoint: URL
    private let configuredHost: String
    private let apiKey: String?
    private let client: any PlateHTTPClient

    public init(
        endpoint: URL,
        apiKey: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.configuredHost = endpoint.host ?? ""
        self.apiKey = apiKey
        self.client = URLSessionPlateHTTPClient(session: urlSession)
    }

    init(
        endpoint: URL,
        apiKey: String? = nil,
        client: any PlateHTTPClient
    ) {
        self.endpoint = endpoint
        self.configuredHost = endpoint.host ?? ""
        self.apiKey = apiKey
        self.client = client
    }

    public func candidates(
        from imageData: Data,
        enabled: Bool
    ) async throws -> [PlateMatchCandidate] {
        guard enabled else { return [] }
        guard let crop = PlateImagePreparer.jpegCrop(from: imageData) else {
            throw PlateMatchError.unreadableImage
        }
        let request = try PlateMatchRequestBuilder.make(
            url: endpoint,
            configuredHost: configuredHost,
            apiKey: apiKey,
            jpegCrop: crop
        )
        let response: PlateHTTPResponse
        do {
            response = try await client.data(for: request)
        } catch {
            throw PlateMatchError.serviceUnavailable
        }
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(PlateMatchResponse.self, from: response.data)
        else { throw PlateMatchError.invalidResponse }
        return payload.candidates.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.confidence.isFinite
                && (0...1).contains($0.confidence)
                && ($0.kilojoulesPer100g.map { $0.isFinite && $0 >= 0 } ?? true)
                && ($0.servingGrams.map { $0.isFinite && $0 > 0 } ?? true)
        }
    }
}

private struct PlateMatchResponse: Decodable, Sendable {
    var candidates: [PlateMatchCandidate]
}
