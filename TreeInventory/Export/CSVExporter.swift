//
//  CSVExporter.swift
//  TreeInventory
//

import Foundation

nonisolated enum CSVExporter {

    private static let headers = [
        "ec5_uuid", "created_at", "uploaded_at", "title",
        "1_Surveyor_Name",
        "lat_2_Location", "long_2_Location", "accuracy_2_Location",
        "UTM_Northing_2_Location", "UTM_Easting_2_Location", "UTM_Zone_2_Location",
        "3_Park_Location", "4_Tree_ID", "5_Photo",
        "6_Diameter_at_Breast", "7_Tree_Height_ft",
        "8_Tree_Spread_tip_to", "9_Tree_Spread_tip_to",
        "10_Tree_Condition", "11_Notes_eg_mushroom", "Species"
    ]

    static func csvString(for records: [TreeRecord]) -> String {
        let iso = ISO8601DateFormatter()

        var lines: [String] = [headers.map(escape).joined(separator: ",")]

        for r in records {
            let notesField = buildNotes(r)
            let conditionLabel: String
            switch r.condition {
            case .good: conditionLabel = "Good"
            case .fair: conditionLabel = "Fair"
            case .poor: conditionLabel = "Poor"
            }

            let row: [String] = [
                r.id.uuidString,
                iso.string(from: r.timestamp),
                r.uploadedAt.map { iso.string(from: $0) } ?? "",
                r.id.uuidString,
                r.surveyorName,
                String(r.latitude),
                String(r.longitude),
                String(r.gpsAccuracy),
                String(r.utmNorthing),
                String(r.utmEasting),
                r.utmZone,
                r.siteCode,
                r.treeId,
                r.photoURL ?? "", // local filename (Documents/TreePhotos/) until Supabase upload is wired up
                r.dbhInches.map { String($0) } ?? "",
                r.heightFeet.map { String($0) } ?? "",
                r.spread1Feet.map { String($0) } ?? "",
                r.spread2Feet.map { String($0) } ?? "",
                conditionLabel,
                notesField,
                r.species
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func buildNotes(_ r: TreeRecord) -> String {
        let typeLabel: String
        switch r.treeType {
        case .largeMatureTree:  typeLabel = "Large mature tree"
        case .youngTree:        typeLabel = "Young tree"
        case .newlyPlantedTree: typeLabel = "Newly planted tree"
        }

        var parts = [typeLabel]
        if r.isMultiBranch { parts.append("multi-branch") }
        if !r.notes.isEmpty { parts.append(r.notes) }
        return parts.joined(separator: "; ")
    }

    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuoting {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - Temp file helper used by ShareSheet

extension CSVExporter {
    nonisolated static func temporaryFileURL(for records: [TreeRecord], projectName: String) throws -> URL {
        let csv = csvString(for: records)
        let fileName = "\(projectName)_trees.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
