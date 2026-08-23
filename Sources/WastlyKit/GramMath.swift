import Foundation

public enum GramMath: Sendable {
    /// leftover = offered - eaten when offered is present; otherwise wasted is entered directly.
    public static func leftoverGrams(offered: Double?, eaten: Double, wasted: Double) -> Double {
        if let offered {
            return max(0, offered - eaten)
        }
        return max(0, wasted)
    }

    public static func split(offered: Double, eaten: Double) -> (eaten: Double, wasted: Double) {
        let clampedEaten = min(max(0, eaten), max(0, offered))
        return (clampedEaten, max(0, offered - clampedEaten))
    }
}
