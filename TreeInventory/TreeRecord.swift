//
//  TreeRecord.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import Foundation
import SwiftData

enum TreeType: String, Codable {
    case largeMatureTree
    case youngTree
    case newlyPlantedTree
}

enum TreeCondition: String, Codable {
    case good
    case fair
    case poor
}

@Model
final class TreeRecord {
    @Attribute(.unique) var id: UUID
    var project: Project?

    // Who/when/where
    var surveyorName: String
    var deviceId: String
    var timestamp: Date       // → created_at / collected_at
    var uploadedAt: Date?     // → uploaded_at

    // GPS (computed from CoreLocation at capture time)
    var latitude: Double
    var longitude: Double
    var gpsAccuracy: Double
    var utmNorthing: Double
    var utmEasting: Double
    var utmZone: String

    // Site & identity
    var siteCode: String      // selected from project.siteCodes
    var treeId: String

    // Measurements (sensor-computed; always directly editable)
    var dbhInches: Double?
    var heightFeet: Double?
    var spread1Feet: Double?
    var spread2Feet: Double?

    // Classification — treeType derived from dbhInches >= 20 by default, but stored so it can be overridden
    var treeType: TreeType
    var isMultiBranch: Bool
    var condition: TreeCondition

    // Inventory fields
    var species: String
    var notes: String
    var photoURL: String?

    // QA artifact — not exported to CSV
    var pointCloudSliceRef: String?

    init(
        id: UUID = UUID(),
        project: Project? = nil,
        surveyorName: String = "",
        deviceId: String = "",
        timestamp: Date = Date(),
        uploadedAt: Date? = nil,
        latitude: Double = 0,
        longitude: Double = 0,
        gpsAccuracy: Double = 0,
        utmNorthing: Double = 0,
        utmEasting: Double = 0,
        utmZone: String = "",
        siteCode: String = "",
        treeId: String = "",
        dbhInches: Double? = nil,
        heightFeet: Double? = nil,
        spread1Feet: Double? = nil,
        spread2Feet: Double? = nil,
        treeType: TreeType = .largeMatureTree,
        isMultiBranch: Bool = false,
        condition: TreeCondition = .good,
        species: String = "",
        notes: String = "",
        photoURL: String? = nil,
        pointCloudSliceRef: String? = nil
    ) {
        self.id = id
        self.project = project
        self.surveyorName = surveyorName
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.uploadedAt = uploadedAt
        self.latitude = latitude
        self.longitude = longitude
        self.gpsAccuracy = gpsAccuracy
        self.utmNorthing = utmNorthing
        self.utmEasting = utmEasting
        self.utmZone = utmZone
        self.siteCode = siteCode
        self.treeId = treeId
        self.dbhInches = dbhInches
        self.heightFeet = heightFeet
        self.spread1Feet = spread1Feet
        self.spread2Feet = spread2Feet
        self.treeType = treeType
        self.isMultiBranch = isMultiBranch
        self.condition = condition
        self.species = species
        self.notes = notes
        self.photoURL = photoURL
        self.pointCloudSliceRef = pointCloudSliceRef
    }
}
