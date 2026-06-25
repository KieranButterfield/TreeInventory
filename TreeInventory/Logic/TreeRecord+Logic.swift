//
//  TreeRecord+Logic.swift
//  TreeInventory
//

import Foundation

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
        return String(format: "%.1f ft", h)
    }

    var displaySpread: String {
        guard let s1 = spread1Feet, let s2 = spread2Feet else { return "—" }
        return String(format: "%.1f × %.1f ft", s1, s2)
    }
}
