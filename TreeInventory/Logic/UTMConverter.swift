//
//  UTMConverter.swift
//  TreeInventory
//

import Foundation

enum UTMConverter {

    // WGS84 ellipsoid constants
    private static let a: Double = 6_378_137.0          // semi-major axis (m)
    private static let f: Double = 1.0 / 298.257_223_563
    private static let k0: Double = 0.9996               // scale factor
    private static let E0: Double = 500_000.0            // false easting (m)
    private static let N0_south: Double = 10_000_000.0  // false northing for southern hemisphere

    static func convert(
        latitude: Double,
        longitude: Double
    ) -> (northing: Double, easting: Double, zone: String) {

        let b = a * (1.0 - f)
        let e2 = 1.0 - (b * b) / (a * a)          // eccentricity squared
        let e_prime2 = e2 / (1.0 - e2)

        let zoneNumber = Int(floor((longitude + 180.0) / 6.0)) + 1
        let zoneLetter = latitudeBandLetter(latitude: latitude)

        let lonOrigin = Double((zoneNumber - 1) * 6 - 180) + 3.0  // central meridian

        let latRad = latitude * .pi / 180.0
        let lonRad = longitude * .pi / 180.0
        let lonOriginRad = lonOrigin * .pi / 180.0

        let N = a / sqrt(1.0 - e2 * sin(latRad) * sin(latRad))
        let T = tan(latRad) * tan(latRad)
        let C = e_prime2 * cos(latRad) * cos(latRad)
        let A = cos(latRad) * (lonRad - lonOriginRad)

        // Meridional arc
        let e4 = e2 * e2
        let e6 = e4 * e2
        let M = a * (
            (1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * latRad
            - (3.0 * e2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * sin(2.0 * latRad)
            + (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * sin(4.0 * latRad)
            - (35.0 * e6 / 3072.0) * sin(6.0 * latRad)
        )

        let easting = k0 * N * (
            A
            + (1.0 - T + C) * pow(A, 3) / 6.0
            + (5.0 - 18.0 * T + T * T + 72.0 * C - 58.0 * e_prime2) * pow(A, 5) / 120.0
        ) + E0

        let northingRaw = k0 * (
            M
            + N * tan(latRad) * (
                A * A / 2.0
                + (5.0 - T + 9.0 * C + 4.0 * C * C) * pow(A, 4) / 24.0
                + (61.0 - 58.0 * T + T * T + 600.0 * C - 330.0 * e_prime2) * pow(A, 6) / 720.0
            )
        )
        let northing = latitude < 0 ? northingRaw + N0_south : northingRaw

        let zone = "\(zoneNumber)\(zoneLetter)"
        return (northing: northing, easting: easting, zone: zone)
    }

    // MGRS/UTM latitude band letters (C–X, omitting I and O)
    private static func latitudeBandLetter(latitude: Double) -> String {
        let bands = "CDEFGHJKLMNPQRSTUVWX"
        // Bands start at -80° in 8° increments; X band covers 72°–84°
        let index: Int
        if latitude >= 72.0 && latitude <= 84.0 {
            index = 19  // X
        } else {
            let i = Int(floor((latitude + 80.0) / 8.0))
            index = max(0, min(i, 19))
        }
        let idx = bands.index(bands.startIndex, offsetBy: index)
        return String(bands[idx])
    }
}
