import Foundation
import SwiftData

public enum WastlyContainer {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(WastlySchema.models), configurations: config)
    }
}
