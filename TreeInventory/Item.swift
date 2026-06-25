//
//  Item.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
