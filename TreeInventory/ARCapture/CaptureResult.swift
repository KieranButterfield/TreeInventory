//
//  CaptureResult.swift
//  TreeInventory
//
//  Shared result type passed back to the UI layer from all AR/sensor capture modules.
//

import Foundation

/// The result of an AR or sensor-based measurement capture session.
/// Any field may be nil if the corresponding measurement was not taken.
struct CaptureResult {
    /// Diameter at breast height, in inches (derived from LiDAR circle fit).
    var dbhInches: Double?

    /// Tree height in feet (derived from CoreMotion tangent-angle method).
    var heightFeet: Double?

    /// Crown spread — first axis — in feet.
    var spread1Feet: Double?

    /// Crown spread — second axis — in feet.
    var spread2Feet: Double?

    /// JSON string of the [x, z] vertex array from the LiDAR slice used for DBH fit.
    /// QA artifact only — not exported to CSV.
    var pointCloudSliceRef: String?
}
