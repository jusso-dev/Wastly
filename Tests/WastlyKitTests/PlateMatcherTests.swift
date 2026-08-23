import Foundation
import ImageIO
import Testing
@testable import WastlyKit

struct PlateMatcherTests {
    @Test func defaultSettingNeverCallsTheCloudMatcher() async throws {
        #expect(AppSettings().ocrCloudEnabled == false)
        let client = RecordingPlateClient()
        let matcher = RemotePlateMatcher(
            endpoint: URL(string: "https://plates.example/v1/match")!,
            apiKey: "fixture-key",
            client: client
        )

        let candidates = try await matcher.candidates(
            from: Data("not even an image".utf8),
            enabled: false
        )

        #expect(candidates.isEmpty)
        #expect(await client.recordedRequests().isEmpty)
    }

    @Test func requestContainsOnlyMetadataFreeCompressedCrop() async throws {
        let imageData = try fixtureImageData()
        let crop = try #require(PlateImagePreparer.jpegCrop(from: imageData))
        #expect(crop.count < imageData.count)

        let source = try #require(CGImageSourceCreateWithData(crop as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == image.height)
        #expect(image.width <= 768)
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let technicalExifKeys: Set<CFString> = [
            kCGImagePropertyExifColorSpace,
            kCGImagePropertyExifPixelXDimension,
            kCGImagePropertyExifPixelYDimension,
        ]
        let exifKeys = Set(exif?.keys.map { $0 } ?? [])
        #expect(exifKeys.isSubset(of: technicalExifKeys))
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
        #expect(tiff?[kCGImagePropertyTIFFDateTime] == nil)

        let endpoint = URL(string: "https://plates.example/v1/match")!
        let request = try PlateMatchRequestBuilder.make(
            url: endpoint,
            configuredHost: "plates.example",
            apiKey: "fixture-key",
            jpegCrop: crop
        )
        #expect(request.url == endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        let body = try #require(request.httpBody)
        try PrivacyGuard.assertPlateJSON(body)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(Set(object.keys) == ["image", "mimeType"])
        #expect(object["mimeType"] as? String == "image/jpeg")
        #expect(Data(base64Encoded: object["image"] as? String ?? "") == crop)
    }

    @Test func configuredMatcherReturnsCandidatesForParentConfirmation() async throws {
        let client = RecordingPlateClient()
        let matcher = RemotePlateMatcher(
            endpoint: URL(string: "https://plates.example/v1/match")!,
            apiKey: "fixture-key",
            client: client
        )

        let candidates = try await matcher.candidates(
            from: fixtureImageData(),
            enabled: true
        )

        #expect(await client.recordedRequests().count == 1)
        #expect(candidates.count == 2)
        #expect(candidates[0].name == "Pasta")
        #expect(candidates[0].foodHit.origin == .cloudPlate)
        #expect(candidates[0].foodHit.kilojoulesPer100g == 650)
    }

    @Test func requestRejectsUnconfiguredOrInsecureDestinations() {
        let crop = Data([0xFF, 0xD8, 0xFF])
        #expect(throws: PrivacyError.self) {
            try PlateMatchRequestBuilder.make(
                url: URL(string: "https://evil.example/v1/match")!,
                configuredHost: "plates.example",
                apiKey: nil,
                jpegCrop: crop
            )
        }
        #expect(throws: PrivacyError.self) {
            try PlateMatchRequestBuilder.make(
                url: URL(string: "http://plates.example/v1/match")!,
                configuredHost: "plates.example",
                apiKey: nil,
                jpegCrop: crop
            )
        }
        #expect(throws: PrivacyError.self) {
            try PrivacyGuard.assertPlateJSON(
                Data(#"{"CHILD":{"firstName":"Sam"}}"#.utf8)
            )
        }
    }

    private func fixtureImageData() throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: "nutrition-label-energy",
                withExtension: "jpg"
            )
        )
        return try Data(contentsOf: url)
    }
}

private actor RecordingPlateClient: PlateHTTPClient {
    private var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> PlateHTTPResponse {
        requests.append(request)
        return PlateHTTPResponse(
            data: Data(
                #"{"candidates":[{"id":"pasta","name":"Pasta","confidence":0.82,"kilojoulesPer100g":650,"servingGrams":120},{"id":"rice","name":"Rice","confidence":0.61},{"id":"bad","name":"Bad","confidence":1.4,"kilojoulesPer100g":-1}]}"#.utf8
            ),
            statusCode: 200
        )
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
