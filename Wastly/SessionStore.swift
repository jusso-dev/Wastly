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
