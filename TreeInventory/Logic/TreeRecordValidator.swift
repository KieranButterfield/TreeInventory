//
//  TreeRecordValidator.swift
//  TreeInventory
//

import Foundation

enum TreeRecordValidator {

    static func validate(_ record: TreeRecord) -> [String] {
        var errors: [String] = []
        if record.surveyorName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Surveyor name is required.")
        }
        if record.siteCode.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Site code is required.")
        }
        if record.treeId.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Tree ID is required.")
        }
        return errors
    }
}
