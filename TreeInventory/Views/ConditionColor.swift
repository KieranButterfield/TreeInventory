//
//  ConditionColor.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI

extension TreeCondition {
    var color: Color {
        switch self {
        case .good: .green
        case .fair: .yellow
        case .poor: .red
        }
    }

    var label: String {
        switch self {
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        }
    }
}
