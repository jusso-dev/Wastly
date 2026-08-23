import Foundation
import SwiftData

public enum WastlyContainer {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let schema = Schema(versionedSchema: WastlySchema.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: WastlyMigrationPlan.self,
            configurations: config
        )
    }
}
