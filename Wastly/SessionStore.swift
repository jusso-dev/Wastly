import Foundation
import LocalAuthentication
import SwiftData
import SwiftUI
import WastlyKit

@MainActor
final class SessionStore: ObservableObject {
    let container: ModelContainer
    let store: LocalFoodStore
    let directory: LocalFirstFoodDirectory
    let labelOCR: NutritionLabelOCR
    let plateMatcher: RemotePlateMatcher?
    let factGenerator: RemoteFactGenerator?

    @Published var selectedChildID: UUID?
    @Published var isLocked: Bool
    @Published var showingOnboarding: Bool
    @Published var diaryFilter: DiaryFilter = .all
    @Published var diaryDay: Date = .now

    enum DiaryFilter: String, CaseIterable, Identifiable {
        case all
        case eaten
        case wasted
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .eaten: "Eaten only"
            case .wasted: "Wasted only"
            }
        }
    }

    init(container: ModelContainer) {
        self.container = container
        self.store = LocalFoodStore(container: container)
        self.labelOCR = NutritionLabelOCR()
        self.plateMatcher = Self.configuredPlateMatcher()
        self.factGenerator = Self.configuredFactGenerator()
        self.directory = LocalFirstFoodDirectory(
            store: store,
            live: RemoteFoodLookup(usdaAPIKey: Self.usdaAPIKey())
        )
        let context = ModelContext(container)
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        let settings = Self.settings(in: context)
        self.selectedChildID = children.sorted { $0.createdAt < $1.createdAt }.first?.id
        self.showingOnboarding = children.isEmpty
        self.isLocked = settings.faceIDEnabled
        Task { await store.insertSeedIfEmpty() }
    }

    static func bootstrap() throws -> SessionStore {
        let container = try WastlyContainer.make()
        return SessionStore(container: container)
    }

    private static func usdaAPIKey() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "USDAAPIKey") as? String else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !key.contains("$("),
              key != "paste-your-data-gov-key-here"
        else { return nil }
        return key
    }

    private static func configuredPlateMatcher() -> RemotePlateMatcher? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "PlateMatchURL") as? String else {
            return nil
        }
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let host = url.host,
              PrivacyAllowlist.isAllowedPlateMatchURL(url, configuredHost: host)
        else { return nil }

        let rawKey = Bundle.main.object(forInfoDictionaryKey: "PlateMatchAPIKey") as? String
        let trimmedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String?
        if let trimmedKey,
           !trimmedKey.isEmpty,
           !trimmedKey.contains("$("),
           trimmedKey != "paste-your-plate-matcher-key-here" {
            key = trimmedKey
        } else {
            key = nil
        }
        return RemotePlateMatcher(endpoint: url, apiKey: key)
    }

    private static func configuredFactGenerator() -> RemoteFactGenerator? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "FactServiceURL") as? String else {
            return nil
        }
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let host = url.host,
              PrivacyAllowlist.isAllowedLLMURL(url, configuredHosts: [host])
        else { return nil }

        let rawKey = Bundle.main.object(forInfoDictionaryKey: "FactServiceAPIKey") as? String
        let trimmedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String?
        if let trimmedKey,
           !trimmedKey.isEmpty,
           !trimmedKey.contains("$("),
           trimmedKey != "paste-your-fact-service-key-here" {
            key = trimmedKey
        } else {
            key = nil
        }
        return RemoteFactGenerator(endpoint: url, apiKey: key)
    }

    static func settings(in context: ModelContext) -> AppSettings {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let row = existing.first { return row }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    func refreshLockFromSettings() {
        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        if !settings.faceIDEnabled {
            isLocked = false
        }
    }

    func unlock() async {
        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        guard settings.faceIDEnabled else {
            isLocked = false
            return
        }
        let auth = LAContext()
        var error: NSError?
        guard auth.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = true
            return
        }
        do {
            let ok = try await auth.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock the Wastly diary"
            )
            isLocked = !ok
        } catch {
            isLocked = true
        }
    }

    func lockIfNeeded() {
        let context = ModelContext(container)
        isLocked = Self.settings(in: context).faceIDEnabled
    }
}

enum DayLogs {
    static func filtered(logs: [FoodLog], day: Date, filter: SessionStore.DiaryFilter) -> [FoodLog] {
        DiaryDay.logs(logs, on: day).filter { log in
            switch filter {
            case .all: return true
            case .eaten: return log.eatenGrams > 0
            case .wasted: return log.wastedGrams > 0
            }
        }
    }
}
