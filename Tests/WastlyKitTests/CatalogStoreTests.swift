import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct CatalogStoreTests {
    @Test func seedBarcodeWorksOffline() async throws {
        let store = try LocalFoodStore.inMemory()
        try await store.insertSeedIfEmpty()
        let hit = await store.barcodeLocal(Barcode.normalized("09300652804562"))
        #expect(hit?.name == "Weet-Bix")
    }

    @Test func upsertDoesNotDuplicate() async throws {
        let store = try LocalFoodStore.inMemory()
        try await store.upsertCatalog(SeedCatalog.foods, version: 1)
        try await store.upsertCatalog(SeedCatalog.foods, version: 2)
        let first = await store.searchLocal("Weet")
        #expect(first.filter { $0.name == "Weet-Bix" }.count == 1)
    }

    @Test func offlineMissDoesNotCrash() async throws {
        let store = try LocalFoodStore.inMemory()
        let directory = LocalFirstFoodDirectory(store: store)
        let result = await directory.barcode("9999999999999", online: false)
        #expect(result.hits.isEmpty)
        #expect(result.miss == .offline || result.miss == .unknownBarcode)
    }
}

struct CatalogSyncTests {
    @Test func multiplePacksCommitOnceAndRemainAvailableOffline() async throws {
        let store = try LocalFoodStore.inMemory()
        try await store.insertSeedIfEmpty()
        let firstFood = SeedFood(
            name: "Woolies Oats",
            brand: "Woolworths",
            barcode: "09310000000001",
            kilojoulesPer100g: 1_500,
            servingGrams: 40
        )
        let secondFood = SeedFood(
            name: "Coles Yoghurt",
            brand: "Coles",
            barcode: "9300000000002",
            kilojoulesPer100g: 420,
            servingGrams: 100
        )
        let client = FixtureCatalogHTTPClient(responses: [
            try response(CatalogPack(
                version: 7,
                etag: "pack-v7",
                pack: 1,
                totalPacks: 2,
                foods: [firstFood]
            ), etag: "\"pack-v7\""),
            try response(CatalogPack(
                version: 7,
                pack: 2,
                totalPacks: 2,
                foods: [secondFood]
            ))
        ])
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client
        )

        let endpoint = try #require(
            URL(string: "https://catalog.example/v1/foods?child=Sam&token=secret")
        )
        let result = try await sync.pull(from: endpoint)

        #expect(result.status == .updated)
        #expect(result.downloadedPacks == 2)
        #expect(result.downloadedRows == 2)
        #expect(result.snapshot.version == 7)
        #expect(result.snapshot.etag == "\"pack-v7\"")
        #expect(result.snapshot.rowCount == SeedCatalog.foods.count + 2)

        let directory = LocalFirstFoodDirectory(store: store)
        let offline = await directory.barcode("9310000000001", online: false)
        #expect(offline.hits.first?.name == "Woolies Oats")

        assertCatalogRequests(await client.recordedRequests())
    }

    @Test func etagNotModifiedAvoidsARewrite() async throws {
        let store = try LocalFoodStore.inMemory()
        let originalDate = Date(timeIntervalSince1970: 1)
        _ = try await store.commitCatalog(
            [SeedFood(name: "Existing", barcode: "9300000000003", kilojoulesPer100g: 300)],
            version: 5,
            etag: "\"v5\"",
            syncedAt: originalDate
        )
        let client = FixtureCatalogHTTPClient(responses: [
            CatalogHTTPResponse(data: Data(), statusCode: 304, etag: "\"v5\"")
        ])
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client
        )

        let result = try await sync.pull(from: try #require(URL(string: "https://catalog.example/catalog")))

        #expect(result.status == .notModified)
        #expect(result.snapshot.version == 5)
        #expect(result.snapshot.rowCount == 1)
        #expect(try #require(result.snapshot.lastSuccessAt) > originalDate)
        let request = try #require(await client.recordedRequests().first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"v5\"")
    }

    @Test func failedLaterPackKeepsThePreviousVersionAtomic() async throws {
        let store = try LocalFoodStore.inMemory()
        _ = try await store.commitCatalog(
            [SeedFood(name: "Good previous row", barcode: "9300000000004", kilojoulesPer100g: 400)],
            version: 5,
            etag: "\"v5\""
        )
        let client = FixtureCatalogHTTPClient(
            responses: [
                try response(CatalogPack(
                    version: 6,
                    pack: 1,
                    totalPacks: 2,
                    foods: [SeedFood(
                        name: "Uncommitted row",
                        barcode: "9300000000005",
                        kilojoulesPer100g: 500
                    )]
                ))
            ],
            failureAt: 1
        )
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client
        )

        var didFail = false
        do {
            _ = try await sync.pull(from: try #require(URL(string: "https://catalog.example/catalog")))
        } catch {
            didFail = true
        }

        #expect(didFail)
        let snapshot = await store.catalogSnapshot()
        #expect(snapshot.version == 5)
        #expect(snapshot.lastError != nil)
        #expect(await store.barcodeLocal(Barcode.normalized("9300000000004"))?.name == "Good previous row")
        #expect(await store.barcodeLocal(Barcode.normalized("9300000000005")) == nil)
    }

    @Test func cancellationKeepsThePreviousVersionAtomic() async throws {
        let store = try LocalFoodStore.inMemory()
        _ = try await store.commitCatalog(
            [SeedFood(name: "Previous", barcode: "9300000000008", kilojoulesPer100g: 800)],
            version: 8,
            etag: "\"v8\""
        )
        let client = SuspendingCatalogHTTPClient()
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client
        )
        let pull = Task {
            try await sync.pull(from: try #require(URL(string: "https://catalog.example/catalog")))
        }
        while !(await client.hasStarted()) {
            await Task.yield()
        }

        pull.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await pull.value
        }

        let snapshot = await store.catalogSnapshot()
        #expect(snapshot.version == 8)
        #expect(snapshot.lastError?.contains("cancelled") == true)
        #expect(await store.barcodeLocal(Barcode.normalized("9300000000008"))?.name == "Previous")
    }

    @Test func rowLimitRejectsThePackBeforeCommit() async throws {
        let store = try LocalFoodStore.inMemory()
        _ = try await store.commitCatalog(
            [SeedFood(name: "Previous", barcode: "9300000000009", kilojoulesPer100g: 900)],
            version: 9,
            etag: "\"v9\""
        )
        let client = FixtureCatalogHTTPClient(responses: [
            try response(CatalogPack(
                version: 10,
                foods: [
                    SeedFood(name: "First", barcode: "9300000000010", kilojoulesPer100g: 100),
                    SeedFood(name: "Second", barcode: "9300000000011", kilojoulesPer100g: 200)
                ]
            ))
        ])
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client,
            maximumRows: 1
        )

        await #expect(throws: CatalogSyncError.tooManyRows(limit: 1)) {
            _ = try await sync.pull(from: try #require(URL(string: "https://catalog.example/catalog")))
        }

        let snapshot = await store.catalogSnapshot()
        #expect(snapshot.version == 9)
        #expect(snapshot.rowCount == 1)
        #expect(await store.barcodeLocal(Barcode.normalized("9300000000010")) == nil)
    }

    @Test func totalDownloadBytesAreBoundedBeforeDecode() async throws {
        let store = try LocalFoodStore.inMemory()
        let client = FixtureCatalogHTTPClient(responses: [
            try response(CatalogPack(
                version: 1,
                foods: [SeedFood(name: "Food", barcode: "9300000000013", kilojoulesPer100g: 1)]
            ))
        ])
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client,
            maximumDownloadBytes: 1
        )

        await #expect(throws: CatalogSyncError.downloadTooLarge(limitBytes: 1)) {
            _ = try await sync.pull(from: try #require(URL(string: "https://catalog.example/catalog")))
        }
        #expect(await store.catalogSnapshot().version == 0)
    }

    @Test func inconsistentPackCountNeverCommitsAPartialVersion() async throws {
        let store = try LocalFoodStore.inMemory()
        let food = SeedFood(name: "Food", barcode: "9300000000015", kilojoulesPer100g: 1)
        let client = FixtureCatalogHTTPClient(responses: [
            try response(CatalogPack(version: 1, pack: 1, totalPacks: 3, foods: [food])),
            try response(CatalogPack(version: 1, pack: 2, totalPacks: 2, foods: [food]))
        ])
        let sync = CatalogSync(
            store: store,
            extraHosts: ["catalog.example"],
            client: client
        )

        await #expect(throws: CatalogSyncError.inconsistentPackCount) {
            _ = try await sync.pull(from: try #require(URL(string: "https://catalog.example/catalog")))
        }
        #expect(await store.catalogSnapshot().version == 0)
    }
}

struct CatalogFixtureTests {
    @Test func fixtureDumpPersistsAcrossAReopenAndReportsBoundedSize() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WastlyCatalogFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let storeURL = directoryURL.appendingPathComponent("wastly.store")
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "catalog-pack-256", withExtension: "json")
        )
        let fixtureData = try Data(contentsOf: fixtureURL)

        do {
            let container = try WastlyContainer.make(url: storeURL)
            let store = LocalFoodStore(container: container)
            let client = FixtureCatalogHTTPClient(responses: [
                CatalogHTTPResponse(data: fixtureData, statusCode: 200, etag: "\"fixture-v42\"")
            ])
            let sync = CatalogSync(
                store: store,
                extraHosts: ["catalog.example"],
                client: client,
                maximumRows: 300
            )
            let result = try await sync.pull(
                from: try #require(URL(string: "https://catalog.example/catalog"))
            )
            #expect(result.downloadedRows == 256)
            #expect(result.snapshot.rowCount == 256)
            #expect(result.snapshot.estimatedBytes > 0)
            #expect(result.snapshot.estimatedBytes < 100_000)
        }

        let reopened = try WastlyContainer.make(url: storeURL)
        let store = LocalFoodStore(container: reopened)
        let directory = LocalFirstFoodDirectory(store: store)
        let result = await directory.barcode("9300000000000", online: false)
        #expect(result.hits.first?.name == "Woolies Fixture Oats")
        #expect(await store.searchLocal("woolies fixture").first?.name == "Woolies Fixture Oats")
    }
}

struct CatalogRetentionTests {
    @Test func clearCatalogKeepsSeedCustomFoodAndDiary() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let store = LocalFoodStore(container: container)
        try await store.insertSeedIfEmpty()
        _ = try await store.commitCatalog(
            [
                SeedFood(name: "Downloaded", barcode: "9300000000006", kilojoulesPer100g: 600),
                SeedFood(
                    name: "Downloaded seed override",
                    barcode: "09300652804562",
                    kilojoulesPer100g: 999
                )
            ],
            version: 9,
            etag: "\"v9\""
        )
        await store.saveCustom(FoodHit(
            id: "custom:family-toast",
            name: "Family toast",
            kilojoulesPer100g: 1_100,
            origin: .custom
        ))
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        context.insert(FoodLog(
            meal: .breakfast,
            foodName: "Family toast",
            eatenGrams: 30,
            wastedGrams: 5,
            kilojoulesPer100g: 1_100,
            child: child
        ))
        try context.save()

        let cleared = try await store.clearDownloadedCatalogLeavingSeedCustomAndLogs()

        #expect(cleared.downloadedRows == 2)
        #expect(cleared.snapshot.version == 0)
        #expect(await store.barcodeLocal(Barcode.normalized("9300000000006")) == nil)
        #expect(await store.barcodeLocal(Barcode.normalized("9300652804562"))?.name == "Weet-Bix")
        #expect(await store.searchLocal("Family toast").first?.origin == .custom)
        let verification = ModelContext(container)
        #expect(try verification.fetch(FetchDescriptor<FoodLog>()).count == 1)
    }

    @Test func backupSnapshotExcludesTheDownloadedCatalog() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let store = LocalFoodStore(container: container)
        _ = try await store.commitCatalog(
            [SeedFood(name: "Downloaded", barcode: "9300000000007", kilojoulesPer100g: 700)],
            version: 2,
            etag: nil
        )
        await store.saveCustom(FoodHit(
            id: "custom:kept",
            name: "Kept custom",
            kilojoulesPer100g: 250,
            origin: .custom
        ))

        let payload = try BackupSnapshot.make(in: ModelContext(container))

        #expect(payload.customFoods.map(\.name) == ["Kept custom"])
        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("Downloaded"))
    }
}
