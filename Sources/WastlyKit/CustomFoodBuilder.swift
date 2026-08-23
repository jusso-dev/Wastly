import Foundation

public enum CustomFoodInputError: Error, Equatable, LocalizedError, Sendable {
    case missingName
    case invalidEnergy
    case invalidServing

    public var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter a name for the custom food."
        case .invalidEnergy:
            "Energy per 100 g must be a valid number that is zero or more."
        case .invalidServing:
            "Serving grams must be a valid number greater than zero."
        }
    }
}

public enum CustomFoodBuilder: Sendable {
    public static func make(
        name: String,
        energyPer100gText: String,
        unit: EnergyUnit,
        servingGramsText: String = ""
    ) throws -> FoodHit {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CustomFoodInputError.missingName }

        let trimmedEnergy = energyPer100gText.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredEnergy: Double
        if trimmedEnergy.isEmpty {
            enteredEnergy = 0
        } else if let value = Double(trimmedEnergy), value.isFinite, value >= 0 {
            enteredEnergy = value
        } else {
            throw CustomFoodInputError.invalidEnergy
        }
        let kilojoules = Energy.storedKilojoules(from: enteredEnergy, unit: unit)

        let trimmedServing = servingGramsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let servingGrams: Double?
        if trimmedServing.isEmpty {
            servingGrams = nil
        } else if let value = Double(trimmedServing), value.isFinite, value > 0 {
            servingGrams = value
        } else {
            throw CustomFoodInputError.invalidServing
        }

        return FoodHit(
            id: "custom:\(trimmedName.lowercased())",
            name: trimmedName,
            kilojoulesPer100g: kilojoules,
            servingGrams: servingGrams,
            origin: .custom
        )
    }
}
