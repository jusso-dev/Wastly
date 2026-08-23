import Foundation

public enum CustomFoodInputError: Error, Equatable, LocalizedError, Sendable {
    case missingName
    case invalidEnergy

    public var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter a name for the custom food."
        case .invalidEnergy:
            "Energy per 100 g must be a valid number that is zero or more."
        }
    }
}

public enum CustomFoodBuilder: Sendable {
    public static func make(
        name: String,
        energyPer100gText: String,
        unit: EnergyUnit
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
        let kilojoules = unit == .kilojoules
            ? enteredEnergy
            : Energy.kilojoules(fromKilocalories: enteredEnergy)

        return FoodHit(
            id: "custom:\(trimmedName.lowercased())",
            name: trimmedName,
            kilojoulesPer100g: kilojoules,
            origin: .custom
        )
    }
}
