import Foundation
import SwiftData

public struct ChildProfileInput: Sendable {
    public var firstName: String
    public var dateOfBirth: Date
    public var photoJPEG: Data?

    public init(firstName: String, dateOfBirth: Date, photoJPEG: Data? = nil) {
        self.firstName = firstName
        self.dateOfBirth = dateOfBirth
        self.photoJPEG = photoJPEG
    }
}

public struct ChildMeasurementInput: Sendable {
    public var recordedAt: Date
    public var heightCentimetres: Double?
    public var weightKilograms: Double?

    public init(
        recordedAt: Date = .now,
        heightCentimetres: Double? = nil,
        weightKilograms: Double? = nil
    ) {
        self.recordedAt = recordedAt
        self.heightCentimetres = heightCentimetres
        self.weightKilograms = weightKilograms
    }
}

public enum ChildProfileError: Error, LocalizedError, Sendable {
    case missingFirstName
    case missingMeasurement
    case invalidMeasurement

    public var errorDescription: String? {
        switch self {
        case .missingFirstName:
            "Enter the child’s first name."
        case .missingMeasurement:
            "Enter a height, a weight, or both."
        case .invalidMeasurement:
            "Height and weight must be numbers greater than zero."
        }
    }
}

public enum ChildProfileStore: Sendable {
    @discardableResult
    public static func create(
        _ input: ChildProfileInput,
        initialMeasurement: ChildMeasurementInput? = nil,
        in context: ModelContext
    ) throws -> Child {
        let firstName = try validatedName(input.firstName)
        let measurement = try initialMeasurement.map(validatedMeasurement)

        do {
            let child = Child(
                firstName: firstName,
                dateOfBirth: input.dateOfBirth,
                photoJPEG: input.photoJPEG
            )
            context.insert(child)
            if let measurement {
                context.insert(makeMeasurement(measurement, child: child))
            }
            try context.save()
            return child
        } catch {
            context.rollback()
            throw error
        }
    }

    public static func update(
        _ child: Child,
        with input: ChildProfileInput,
        newMeasurement: ChildMeasurementInput? = nil,
        in context: ModelContext
    ) throws {
        let firstName = try validatedName(input.firstName)
        let measurement = try newMeasurement.map(validatedMeasurement)

        do {
            child.firstName = firstName
            child.dateOfBirth = input.dateOfBirth
            child.photoJPEG = input.photoJPEG
            if let measurement {
                context.insert(makeMeasurement(measurement, child: child))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public static func addMeasurement(
        _ input: ChildMeasurementInput,
        to child: Child,
        in context: ModelContext
    ) throws {
        let measurement = try validatedMeasurement(input)
        do {
            context.insert(makeMeasurement(measurement, child: child))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public static func delete(_ child: Child, in context: ModelContext) throws {
        do {
            context.delete(child)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func validatedName(_ value: String) throws -> String {
        let firstName = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstName.isEmpty else { throw ChildProfileError.missingFirstName }
        return firstName
    }

    private static func validatedMeasurement(_ input: ChildMeasurementInput) throws -> ChildMeasurementInput {
        guard input.heightCentimetres != nil || input.weightKilograms != nil else {
            throw ChildProfileError.missingMeasurement
        }
        if let height = input.heightCentimetres, height <= 0 {
            throw ChildProfileError.invalidMeasurement
        }
        if let weight = input.weightKilograms, weight <= 0 {
            throw ChildProfileError.invalidMeasurement
        }
        return input
    }

    private static func makeMeasurement(_ input: ChildMeasurementInput, child: Child) -> MeasurementPoint {
        MeasurementPoint(
            recordedAt: input.recordedAt,
            heightCentimetres: input.heightCentimetres,
            weightKilograms: input.weightKilograms,
            child: child
        )
    }
}

public enum ChildSelection: Sendable {
    public static func showsSwitcher(childCount: Int) -> Bool {
        childCount > 1
    }

    public static func logs(for childID: UUID?, from logs: [FoodLog]) -> [FoodLog] {
        guard let childID else { return [] }
        return logs.filter { $0.child?.id == childID }
    }
}
