//
//  Project.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var siteCodes: [String]
    @Relationship(deleteRule: .cascade, inverse: \TreeRecord.project)
    var treeRecords: [TreeRecord]

    init(id: UUID = UUID(), name: String, siteCodes: [String] = []) {
        self.id = id
        self.name = name
        self.siteCodes = siteCodes
        self.treeRecords = []
    }
}
