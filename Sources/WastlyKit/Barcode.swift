import Foundation

public enum Barcode: Sendable {
    /// Exact-match key: strip leading zeros. Empty after strip is treated as no code.
    public static func normalized(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let stripped = String(digits.drop(while: { $0 == "0" }))
        return stripped
    }

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalized(lhs)
        let b = normalized(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b
    }
}
