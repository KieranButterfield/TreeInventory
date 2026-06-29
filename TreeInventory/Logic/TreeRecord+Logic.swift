//
//  TreeRecord+Logic.swift
//  TreeInventory
//

import Foundation

/// Formats a feet value as e.g. "6' 6"", "6'", or "6"" (nearest inch).
func formatFeetInches(_ totalFeet: Double) -> String {
    let totalInches = Int((totalFeet * 12).rounded())
    let feet = totalInches / 12
    let inches = totalInches % 12
    if feet == 0 { return "\(inches)\"" }
    if inches == 0 { return "\(feet)'" }
    return "\(feet)' \(inches)\""
}

/// Parses a user-entered distance in feet. Accepts:
///   "9'8"" or "9' 8""   → 9.667 ft
///   "77"" or "77 in"    → 6.417 ft  (inches-only)
///   "6.5" or "6.5 ft"   → 6.5 ft    (decimal feet)
func parseFeet(_ text: String) -> Double? {
    let s = text.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }
    let lower = s.lowercased()

    // Feet + inches first (contains an apostrophe).
    if lower.contains("'") {
        let parts = lower.components(separatedBy: "'")
        guard parts.count >= 2, let feet = Double(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        let inchStr = parts[1]
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "in", with: "")
            .trimmingCharacters(in: .whitespaces)
        return feet + (Double(inchStr) ?? 0) / 12.0
    }

    // Inches-only: ends with " or an inches keyword.
    if lower.hasSuffix("\"") || lower.hasSuffix("in") || lower.hasSuffix("inches") || lower.hasSuffix("inch") {
        let stripped = lower
            .replacingOccurrences(of: "inches", with: "")
            .replacingOccurrences(of: "inch", with: "")
            .replacingOccurrences(of: "in", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let inches = Double(stripped) { return inches / 12.0 }
        return nil
    }

    // Decimal feet.
    let cleaned = lower
        .replacingOccurrences(of: "feet", with: "")
        .replacingOccurrences(of: "ft", with: "")
        .trimmingCharacters(in: .whitespaces)
    return Double(cleaned)
}

/// Parses a user-entered measurement in inches. Accepts:
///   "14.5" or "14.5"" or "14.5 in"   → 14.5 in
///   "1'2.5""                           → 14.5 in  (feet + inches)
func parseInches(_ text: String) -> Double? {
    let s = text.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }
    let lower = s.lowercased()

    // Feet + inches.
    if lower.contains("'") { return parseFeet(s).map { $0 * 12.0 } }

    let cleaned = lower
        .replacingOccurrences(of: "inches", with: "")
        .replacingOccurrences(of: "inch", with: "")
        .replacingOccurrences(of: "in", with: "")
        .replacingOccurrences(of: "\"", with: "")
        .trimmingCharacters(in: .whitespaces)
    return Double(cleaned)
}

extension TreeType {
    var displayName: String {
        switch self {
        case .largeMatureTree: "Large Mature Tree"
        case .youngTree: "Young Tree"
        case .newlyPlantedTree: "Newly Planted Tree"
        }
    }
}

extension TreeRecord {

    static func derivedTreeType(fromDBH dbhInches: Double?) -> TreeType {
        guard let dbh = dbhInches, dbh >= 20 else { return .youngTree }
        return .largeMatureTree
    }

    var isComplete: Bool {
        guard
            let dbh = dbhInches, dbh > 0,
            let h = heightFeet, h > 0,
            let s1 = spread1Feet, s1 > 0,
            let s2 = spread2Feet, s2 > 0
        else { return false }
        return !siteCode.isEmpty && !treeId.isEmpty
    }

    var displayDBH: String {
        guard let dbh = dbhInches else { return "—" }
        return String(format: "%.1f in", dbh)
    }

    var displayHeight: String {
        guard let h = heightFeet else { return "—" }
        return formatFeetInches(h)
    }

    var displaySpread: String {
        guard let s1 = spread1Feet, let s2 = spread2Feet else { return "—" }
        return "\(formatFeetInches(s1)) × \(formatFeetInches(s2))"
    }
}
