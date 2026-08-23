import Foundation
import SwiftData

public enum WastlyContainer {
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let config = if let url {
            ModelConfiguration(url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
        }
        let schema = Schema(versionedSchema: WastlySchema.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: WastlyMigrationPlan.self,
            configurations: config
        )
    }
}
