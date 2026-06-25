//
//  DeviceID.swift
//  TreeInventory
//

import UIKit

enum DeviceID {
    static var current: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}
