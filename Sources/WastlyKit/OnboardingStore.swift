import Foundation
import SwiftData

public struct OnboardingInput: Sendable {
    public var firstName: String
    public var dateOfBirth: Date
    public var heightCentimetres: Double?
    public var weightKilograms: Double?
    public var faceIDEnabled: Bool
    public var iCloudBackupEnabled: Bool
    public var backupPasswordEnabled: Bool

    public init(
        firstName: String,
        dateOfBirth: Date,
        heightCentimetres: Double? = nil,
        weightKilograms: Double? = nil,
        faceIDEnabled: Bool = false,
        iCloudBackupEnabled: Bool = false,
        backupPasswordEnabled: Bool = false
    ) {
        self.firstName = firstName
        self.dateOfBirth = dateOfBirth
        self.heightCentimetres = heightCentimetres
        self.weightKilograms = weightKilograms
        self.faceIDEnabled = faceIDEnabled
        self.iCloudBackupEnabled = iCloudBackupEnabled
        self.backupPasswordEnabled = backupPasswordEnabled
    }
}

public enum OnboardingError: Error, Sendable {
    case missingFirstName
}

public enum OnboardingStore: Sendable {
    @discardableResult
    public static func save(_ input: OnboardingInput, in context: ModelContext) throws -> Child {
        let firstName = input.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstName.isEmpty else { throw OnboardingError.missingFirstName }

        do {
            let child = Child(firstName: firstName, dateOfBirth: input.dateOfBirth)
            context.insert(child)

            if input.heightCentimetres != nil || input.weightKilograms != nil {
                context.insert(MeasurementPoint(
                    heightCentimetres: input.heightCentimetres,
                    weightKilograms: input.weightKilograms,
                    child: child
                ))
            }

            let settings: AppSettings
            if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first {
                settings = existing
            } else {
                settings = AppSettings()
                context.insert(settings)
            }
            settings.faceIDEnabled = input.faceIDEnabled
            settings.iCloudBackupEnabled = input.iCloudBackupEnabled
            settings.backupPasswordEnabled = input.iCloudBackupEnabled && input.backupPasswordEnabled

            try context.save()
            return child
        } catch {
            context.rollback()
            throw error
        }
    }
}
