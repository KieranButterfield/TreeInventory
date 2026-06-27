//
//  PhotoStorage.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/26/26.
//
//  Saves/loads tree photos as JPEGs under Documents/TreePhotos/.
//  TreeRecord.photoURL stores only the filename (never a full path), so saved
//  references keep working even if the app's sandbox container path changes
//  across reinstalls or OS updates.
//

import UIKit

enum PhotoStorage {
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("TreePhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Saves a photo as a JPEG and returns the filename to store on the record.
    @discardableResult
    static func save(_ image: UIImage, filename: String = UUID().uuidString + ".jpg") -> String? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func load(filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }

    static func delete(filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}
