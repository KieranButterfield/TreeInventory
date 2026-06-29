//
//  TreeDetailView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData
import UIKit

struct TreeDetailView: View {
    @Bindable var record: TreeRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var showingDeleteConfirm = false

    // Edit state
    @State private var editTreeId: String = ""
    @State private var editSpecies: String = ""
    @State private var editCondition: TreeCondition = .good
    @State private var editTreeType: TreeType = .largeMatureTree
    @State private var editIsMultiBranch: Bool = false
    @State private var editNotes: String = ""
    @State private var editSiteCode: String = ""
    @State private var editSurveyorName: String = ""
    @State private var editDbhText: String = ""
    @State private var editHeightText: String = ""
    @State private var editSpread1Text: String = ""
    @State private var editSpread2Text: String = ""
    @State private var editPhotoFilename: String? = nil

    @State private var showingPhotoViewer = false
    @State private var showingCamera = false

    private var dbhProgress: Double {
        min((record.dbhInches ?? 0) / 30.0, 1.0)
    }
    private var heightProgress: Double {
        min((record.heightFeet ?? 0) / 100.0, 1.0)
    }
    private var spreadProgress: Double {
        let maxSpread = max(record.spread1Feet ?? 0, record.spread2Feet ?? 0)
        return min(maxSpread / 60.0, 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isEditing {
                    editingView
                } else {
                    readingView
                }
            }
            .padding()
        }
        .navigationTitle(record.treeId.isEmpty ? "(no ID)" : record.treeId)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveEdits()
                    } else {
                        loadEdits()
                    }
                    withAnimation { isEditing.toggle() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            if let image = PhotoStorage.load(filename: record.photoURL) {
                PhotoViewerView(image: image) { showingPhotoViewer = false }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView(
                onCapture: { image in
                    if let name = PhotoStorage.save(image) {
                        if let old = editPhotoFilename, old != name {
                            PhotoStorage.delete(filename: old)
                        }
                        editPhotoFilename = name
                    }
                    showingCamera = false
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: editDbhText) { _, _ in
            if let dbh = Double(editDbhText.trimmingCharacters(in: .whitespaces)) {
                editTreeType = TreeRecord.derivedTreeType(fromDBH: dbh)
            }
        }
        .alert("Delete this tree?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteTree() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(record.treeId.isEmpty ? "this tree" : record.treeId) and its photo. This can't be undone.")
        }
    }

    // MARK: - Reading View

    private var readingView: some View {
        VStack(spacing: 16) {
            // Card 1: Measurements
            GroupBox {
                VStack(spacing: 14) {
                    MeasurementRow(
                        label: "DBH",
                        value: record.dbhInches.map { String(format: "%.1f in", $0) } ?? "—",
                        progress: dbhProgress
                    )
                    Divider()
                    MeasurementRow(
                        label: "Height",
                        value: record.heightFeet.map { formatFeetInches($0) } ?? "—",
                        progress: heightProgress
                    )
                    Divider()
                    MeasurementRow(
                        label: "Crown Spread",
                        value: spreadDisplayValue,
                        progress: spreadProgress
                    )
                }
            } label: {
                Label("Measurements", systemImage: "ruler")
                    .font(.headline)
            }

            // Card 2: Inventory Information
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(label: "Species", value: record.species.isEmpty ? "—" : record.species)
                    Divider()

                    // Condition with colored pill
                    HStack {
                        Text("Condition")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(record.condition.color)
                                .frame(width: 8, height: 8)
                            Text(record.condition.label)
                                .font(.subheadline)
                                .foregroundStyle(record.condition.color)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(record.condition.color.opacity(0.12), in: Capsule())
                    }
                    Divider()

                    InfoRow(label: "Tree Type", value: record.treeType.displayName)
                    Divider()
                    InfoRow(label: "Multi-branch", value: record.isMultiBranch ? "Yes" : "No")
                    Divider()
                    InfoRow(label: "Site Code", value: record.siteCode.isEmpty ? "—" : record.siteCode)
                    Divider()
                    InfoRow(label: "Surveyor", value: record.surveyorName.isEmpty ? "—" : record.surveyorName)
                    Divider()
                    InfoRow(label: "GPS", value: String(format: "%.6f, %.6f (±%.0fm)", record.latitude, record.longitude, record.gpsAccuracy))
                    Divider()
                    InfoRow(label: "UTM", value: "\(record.utmZone) N: \(Int(record.utmNorthing)) E: \(Int(record.utmEasting))")
                    Divider()
                    InfoRow(label: "Measured", value: record.timestamp.formatted(date: .abbreviated, time: .shortened))

                    if !record.notes.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(record.notes)
                                .font(.body)
                        }
                    }
                }
            } label: {
                Label("Inventory Information", systemImage: "doc.text")
                    .font(.headline)
            }

            // Photo
            Group {
                if let image = PhotoStorage.load(filename: record.photoURL) {
                    Button {
                        showingPhotoViewer = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 100)
                        .overlay(
                            Label("No Photo", systemImage: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
            }

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    openInMaps()
                } label: {
                    Label("Show on Map", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Tree", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if let image = PhotoStorage.load(filename: editPhotoFilename) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        HStack {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Retake", systemImage: "camera.rotate")
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                PhotoStorage.delete(filename: editPhotoFilename)
                                editPhotoFilename = nil
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } label: {
                Label("Photo", systemImage: "photo")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    EditField(label: "Tree ID", text: $editTreeId)
                    Divider()
                    EditField(label: "Species", text: $editSpecies)
                    Divider()
                    EditField(label: "Site Code", text: $editSiteCode)
                    Divider()
                    EditField(label: "Surveyor", text: $editSurveyorName)
                    Divider()
                    EditField(label: "DBH (in)", text: $editDbhText, keyboard: .decimalPad)
                    Divider()
                    EditField(label: "Height (ft)", text: $editHeightText, keyboard: .decimalPad)
                    Divider()
                    EditField(label: "Spread 1 (ft)", text: $editSpread1Text, keyboard: .decimalPad)
                    Divider()
                    EditField(label: "Spread 2 (ft)", text: $editSpread2Text, keyboard: .decimalPad)
                }
            } label: {
                Label("Edit Fields", systemImage: "pencil")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Condition")
                            .font(.subheadline)
                        Spacer()
                        Picker("Condition", selection: $editCondition) {
                            Text("Good").tag(TreeCondition.good)
                            Text("Fair").tag(TreeCondition.fair)
                            Text("Poor").tag(TreeCondition.poor)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    Divider()
                    HStack {
                        Text("Tree Type")
                            .font(.subheadline)
                        Spacer()
                        Picker("Tree Type", selection: $editTreeType) {
                            Text("Large Mature").tag(TreeType.largeMatureTree)
                            Text("Young").tag(TreeType.youngTree)
                            Text("New").tag(TreeType.newlyPlantedTree)
                        }
                        .pickerStyle(.menu)
                    }
                    Divider()
                    Button {
                        editIsMultiBranch.toggle()
                    } label: {
                        HStack {
                            Text("Multi-branch")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: editIsMultiBranch ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(editIsMultiBranch ? Color.green : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                        TextEditor(text: $editNotes)
                            .frame(minHeight: 72)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            } label: {
                Label("Classification", systemImage: "tag")
                    .font(.headline)
            }
        }
    }

    // MARK: - Helpers

    private var spreadDisplayValue: String {
        guard record.spread1Feet != nil || record.spread2Feet != nil else { return "—" }
        let s1 = record.spread1Feet.map { formatFeetInches($0) } ?? "—"
        let s2 = record.spread2Feet.map { formatFeetInches($0) } ?? "—"
        return "\(s1) × \(s2)"
    }

    private func deleteTree() {
        PhotoStorage.delete(filename: record.photoURL)
        modelContext.delete(record)
        dismiss()
    }

    private func openInMaps() {
        let treeLabel = record.treeId.isEmpty ? "Tree" : record.treeId
        let urlString = "maps:?ll=\(record.latitude),\(record.longitude)&q=\(treeLabel)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func loadEdits() {
        editTreeId = record.treeId
        editSpecies = record.species
        editCondition = record.condition
        editTreeType = record.treeType
        editIsMultiBranch = record.isMultiBranch
        editNotes = record.notes
        editSiteCode = record.siteCode
        editSurveyorName = record.surveyorName
        editDbhText = record.dbhInches.map { String(format: "%.2f", $0) } ?? ""
        editHeightText = record.heightFeet.map { formatFeetInches($0) } ?? ""
        editSpread1Text = record.spread1Feet.map { formatFeetInches($0) } ?? ""
        editSpread2Text = record.spread2Feet.map { formatFeetInches($0) } ?? ""
        editPhotoFilename = record.photoURL
    }

    private func saveEdits() {
        record.treeId = editTreeId.trimmingCharacters(in: .whitespaces)
        record.species = editSpecies.trimmingCharacters(in: .whitespaces)
        record.condition = editCondition
        record.treeType = editTreeType
        record.isMultiBranch = editIsMultiBranch
        record.notes = editNotes.trimmingCharacters(in: .whitespaces)
        record.siteCode = editSiteCode.trimmingCharacters(in: .whitespaces)
        record.surveyorName = editSurveyorName.trimmingCharacters(in: .whitespaces)
        record.dbhInches = parseInches(editDbhText.trimmingCharacters(in: .whitespaces))
        record.heightFeet = parseFeet(editHeightText.trimmingCharacters(in: .whitespaces))
        record.spread1Feet = parseFeet(editSpread1Text.trimmingCharacters(in: .whitespaces))
        record.spread2Feet = parseFeet(editSpread2Text.trimmingCharacters(in: .whitespaces))
        record.photoURL = editPhotoFilename
        try? modelContext.save()
    }
}

// MARK: - Sub-components

struct MeasurementRow: View {
    let label: String
    let value: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline.bold())
            }
            ProgressView(value: progress)
                .tint(.accentColor)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct EditField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(label, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PhotoViewerView: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, TreeRecord.self, configurations: config)
    let record = TreeRecord(
        surveyorName: "Jane Smith",
        deviceId: "device-123",
        timestamp: Date(),
        latitude: 51.5074,
        longitude: -0.1278,
        gpsAccuracy: 3.0,
        utmNorthing: 5710000,
        utmEasting: 699000,
        utmZone: "30U",
        siteCode: "A1",
        treeId: "T-001",
        dbhInches: 14.5,
        heightFeet: 42.0,
        spread1Feet: 18.0,
        spread2Feet: 20.0,
        treeType: .largeMatureTree,
        isMultiBranch: true,
        condition: .good,
        species: "Quercus robur"
    )
    container.mainContext.insert(record)
    return NavigationStack {
        TreeDetailView(record: record)
    }
    .modelContainer(container)
}
