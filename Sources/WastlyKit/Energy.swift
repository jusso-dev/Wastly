import Foundation

/// Stored energy is always kilojoules. Display can convert to kcal (4.184 kJ = 1 kcal).
public enum EnergyUnit: String, Codable, Sendable, CaseIterable {
    case kilojoules
    case kilocalories
}

public enum Energy: Sendable {
    public static let kilojoulesPerKilocalorie: Double = 4.184

    public static func kilojoules(fromKilocalories kcal: Double) -> Double {
        kcal * kilojoulesPerKilocalorie
    }

    public static func kilocalories(fromKilojoules kJ: Double) -> Double {
        kJ / kilojoulesPerKilocalorie
    }

    public static func energyKilojoules(grams: Double, kilojoulesPer100g: Double) -> Double {
        guard grams.isFinite, kilojoulesPer100g.isFinite else { return 0 }
        return (grams / 100.0) * kilojoulesPer100g
    }

    public static func display(_ kilojoules: Double, unit: EnergyUnit, fractionDigits: Int = 0) -> String {
        let value = unit == .kilojoules ? kilojoules : kilocalories(fromKilojoules: kilojoules)
        let number = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        return unit == .kilojoules ? "\(number) kJ" : "\(number) kcal"
    }
}
