import Foundation

/// Stored energy is always kilojoules. Display can convert to kcal (4.184 kJ = 1 kcal).
public enum EnergyUnit: String, Codable, Sendable, CaseIterable {
    case kilojoules
    case kilocalories

    public var symbol: String {
        switch self {
        case .kilojoules: "kJ"
        case .kilocalories: "kcal"
        }
    }
}

public enum Energy: Sendable {
    public static let kilojoulesPerKilocalorie: Double = 4.184

    /// Converts a value entered or received in `unit` to the app's kJ storage unit.
    public static func storedKilojoules(from value: Double, unit: EnergyUnit) -> Double {
        switch unit {
        case .kilojoules: value
        case .kilocalories: value * kilojoulesPerKilocalorie
        }
    }

    /// Converts a stored kJ value for presentation without changing the stored value.
    public static func value(fromStoredKilojoules kilojoules: Double, unit: EnergyUnit) -> Double {
        switch unit {
        case .kilojoules: kilojoules
        case .kilocalories: kilojoules / kilojoulesPerKilocalorie
        }
    }

    public static func kilojoules(fromKilocalories kcal: Double) -> Double {
        storedKilojoules(from: kcal, unit: .kilocalories)
    }

    public static func kilocalories(fromKilojoules kilojoules: Double) -> Double {
        value(fromStoredKilojoules: kilojoules, unit: .kilocalories)
    }

    public static func energyKilojoules(grams: Double, kilojoulesPer100g: Double) -> Double {
        guard grams.isFinite, kilojoulesPer100g.isFinite else { return 0 }
        return (grams / 100.0) * kilojoulesPer100g
    }

    public static func display(_ kilojoules: Double, unit: EnergyUnit, fractionDigits: Int = 0) -> String {
        let value = value(fromStoredKilojoules: kilojoules, unit: unit)
        let number = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        return "\(number) \(unit.symbol)"
    }
}
