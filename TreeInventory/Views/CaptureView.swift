//
//  CaptureView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import UIKit

struct CaptureView: View {
    let project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Device-wide "last used" surveyor name (shared with Export tab).
    @AppStorage("surveyorName") private var defaultSurveyorName: String = ""
    @State private var surveyorName: String = ""
    @State private var showingSurveyorPrompt = false
    @State private var surveyorPromptText: String = ""

    @State private var step: Int = 1

    // AR capture sheets
    @State private var showingHeightCapture = false
    @State private var showingDBHCapture = false
    @State private var showingCrownCapture = false

    // Results from AR capture (merged with manual overrides)
    @State private var capturedResult = CaptureResult()

    // Manual override text fields (pre-filled from AR result)
    @State private var heightFeetText: String = ""
    @State private var dbhInchesText: String = ""
    @State private var spread1FeetText: String = ""
    @State private var spread2FeetText: String = ""

    // Step 4 — Details
    @State private var treeId: String = ""
    @State private var selectedSiteCode: String = ""
    @State private var siteCodeText: String = ""
    @State private var condition: TreeCondition = .good
    @State private var treeType: TreeType = .largeMatureTree
    @State private var isMultiBranch: Bool = false
    @State private var species: String = ""
    @State private var notes: String = ""
    @State private var photoFilename: String? = nil
    @State private var showingCamera = false

    @State private var location = LocationManager()
    @State private var hasAppeared = false

    private let totalSteps = 4

    // Looks at every Tree ID already recorded for this project, finds the one
    // with the highest trailing number, and suggests that number + 1 — keeping
    // the same prefix and zero-padding width (e.g. "T-004" -> "T-005").
    // Falls back to "T-001" when there's nothing to go on yet.
    private var suggestedTreeId: String {
        var bestPrefix = "T-"
        var bestWidth = 3
        var maxNumber = 0
        var found = false

        for id in project.treeRecords.map(\.treeId) {
            var digits = ""
            var splitIndex = id.endIndex
            while splitIndex > id.startIndex {
                let prev = id.index(before: splitIndex)
                guard id[prev].isNumber else { break }
                digits.insert(id[prev], at: digits.startIndex)
                splitIndex = prev
            }
            guard !digits.isEmpty, let number = Int(digits), number >= maxNumber || !found else { continue }
            maxNumber = number
            bestPrefix = String(id[id.startIndex..<splitIndex])
            bestWidth = digits.count
            found = true
        }

        guard found else { return "T-001" }
        let nextDigits = String(maxNumber + 1)
        let padded = nextDigits.count < bestWidth
            ? String(repeating: "0", count: bestWidth - nextDigits.count) + nextDigits
            : nextDigits
        return bestPrefix + padded
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepProgressView(current: step, total: totalSteps)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch step {
                        case 1: heightStepView
                        case 2: dbhStepView
                        case 3: crownSpreadStepView
                        case 4: detailsStepView
                        default: EmptyView()
                        }
                    }
                    .padding()
                }

                Divider()

                HStack {
                    if step > 1 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    if step < totalSteps {
                        Button("Next") { withAnimation { step += 1 } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Save") { saveRecord() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("Step \(step) of \(totalSteps)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingHeightCapture) {
                NavigationStack {
                    HeightCaptureView { result in
                        capturedResult.heightFeet = result.heightFeet
                        if let h = result.heightFeet {
                            heightFeetText = formatFeetInches(h)
                        }
                        showingHeightCapture = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingHeightCapture = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDBHCapture) {
                NavigationStack {
                    DBHCaptureView { result in
                        capturedResult.dbhInches = result.dbhInches
                        capturedResult.pointCloudSliceRef = result.pointCloudSliceRef
                        if let d = result.dbhInches {
                            dbhInchesText = String(format: "%.1f", d)
                            treeType = TreeRecord.derivedTreeType(fromDBH: d)
                        }
                        showingDBHCapture = false
                    }
                }
            }
            .sheet(isPresented: $showingCrownCapture) {
                NavigationStack {
                    CrownSpreadCaptureView { result in
                        capturedResult.spread1Feet = result.spread1Feet
                        capturedResult.spread2Feet = result.spread2Feet
                        if let s1 = result.spread1Feet { spread1FeetText = formatFeetInches(s1) }
                        if let s2 = result.spread2Feet { spread2FeetText = formatFeetInches(s2) }
                        showingCrownCapture = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCrownCapture = false }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView(
                onCapture: { image in
                    if let name = PhotoStorage.save(image) {
                        // Replacing a photo? Clean up the old file first.
                        if let old = photoFilename, old != name {
                            PhotoStorage.delete(filename: old)
                        }
                        photoFilename = name
                    }
                    showingCamera = false
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: dbhInchesText) { _, newValue in
            if let dbh = parseInches(newValue.trimmingCharacters(in: .whitespaces)) {
                treeType = TreeRecord.derivedTreeType(fromDBH: dbh)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if let first = project.siteCodes.first { selectedSiteCode = first }
            surveyorName = defaultSurveyorName
            if defaultSurveyorName.trimmingCharacters(in: .whitespaces).isEmpty {
                showingSurveyorPrompt = true
            }
        }
        .alert("Who's surveying?", isPresented: $showingSurveyorPrompt) {
            TextField("Your name", text: $surveyorPromptText)
                .autocorrectionDisabled()
            Button("Save") {
                let trimmed = surveyorPromptText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    surveyorName = trimmed
                    defaultSurveyorName = trimmed
                }
            }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("Saved automatically with each tree you measure. You can change it anytime on the Details step or in Export.")
        }
    }

    // MARK: - Step Views

    private var heightStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Height Measurement", systemImage: "arrow.up.to.line")
                .font(.title2.bold())

            Text("Sight the base and top with AR, or enter a value directly. (Short tree? Just use a tape measure.)")
                .foregroundStyle(.secondary)

            Button {
                showingHeightCapture = true
            } label: {
                Label("Measure Height with AR", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 6) {
                Text(capturedResult.heightFeet != nil ? "AR result — edit if needed:" : "Manual entry (ft)")
                    .font(.subheadline.bold())
                TextField("e.g. 45.0", text: $heightFeetText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var dbhStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("DBH Measurement", systemImage: "circle.dashed")
                .font(.title2.bold())

            Text("Tap the trunk at breast height with AR, or enter a value directly. (Too short? Measure at 6\" and mark as Newly Planted.)")
                .foregroundStyle(.secondary)

            Button {
                showingDBHCapture = true
            } label: {
                Label("Measure DBH with LiDAR", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 6) {
                Text(capturedResult.dbhInches != nil ? "AR result — edit if needed (in):" : "Manual entry — circumference (in)")
                    .font(.subheadline.bold())
                TextField("e.g. 12.5", text: $dbhInchesText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: dbhInchesText) { _, newValue in
                        if let d = parseInches(newValue.trimmingCharacters(in: .whitespaces)) {
                            treeType = TreeRecord.derivedTreeType(fromDBH: d)
                        }
                    }
            }
        }
    }

    private var crownSpreadStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Crown Spread", systemImage: "arrow.left.and.right")
                .font(.title2.bold())

            Text("Crown spread is the average width of the tree's canopy — found by measuring straight across it twice, at a right angle to each other, and averaging the two readings.")
                .foregroundStyle(.secondary)

            Text("Walk to the canopy edge. Take two perpendicular measurements with the AR ruler, or enter values directly.")
                .foregroundStyle(.secondary)

            Button {
                showingCrownCapture = true
            } label: {
                Label("Measure Crown Spread with AR", systemImage: "arrow.left.and.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(capturedResult.spread1Feet != nil ? "Spread 1 — AR result (ft):" : "Spread 1 (ft)")
                        .font(.subheadline.bold())
                    TextField("e.g. 18.0", text: $spread1FeetText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(capturedResult.spread2Feet != nil ? "Spread 2 — AR result (ft):" : "Spread 2 (ft)")
                        .font(.subheadline.bold())
                    TextField("e.g. 20.0", text: $spread2FeetText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var detailsStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Tree Details", systemImage: "doc.text")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Tree ID")
                    .font(.subheadline.bold())
                TextField("e.g. \(suggestedTreeId)", text: $treeId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Surveyor")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("(carries over to the next tree)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Your name", text: $surveyorName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: surveyorName) { _, newValue in
                        defaultSurveyorName = newValue
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Site Code")
                    .font(.subheadline.bold())
                if project.siteCodes.isEmpty {
                    TextField("Site code", text: $siteCodeText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } else {
                    Picker("Site Code", selection: $selectedSiteCode) {
                        ForEach(project.siteCodes, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Condition")
                    .font(.subheadline.bold())
                Picker("Condition", selection: $condition) {
                    Text("Good").tag(TreeCondition.good)
                    Text("Fair").tag(TreeCondition.fair)
                    Text("Poor").tag(TreeCondition.poor)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tree Type")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("(auto-set from DBH)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Picker("Tree Type", selection: $treeType) {
                        Text("Large Mature").tag(TreeType.largeMatureTree)
                        Text("Young").tag(TreeType.youngTree)
                        Text("Newly Planted").tag(TreeType.newlyPlantedTree)
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
            }

            Divider()

            Button {
                isMultiBranch.toggle()
            } label: {
                HStack {
                    Text("Multi-branch")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isMultiBranch ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isMultiBranch ? Color.green : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Species")
                    .font(.subheadline.bold())
                TextField("e.g. Quercus robur", text: $species)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline.bold())
                TextEditor(text: $notes)
                    .frame(minHeight: 72)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Photo")
                    .font(.subheadline.bold())
                if let image = PhotoStorage.load(filename: photoFilename) {
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
                            PhotoStorage.delete(filename: photoFilename)
                            photoFilename = nil
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
        }
    }

    // MARK: - Save

    private func saveRecord() {
        // Prefer manual text entry (allows override of AR result); fall back to AR result
        let dbhValue     = parseInches(dbhInchesText.trimmingCharacters(in: .whitespaces))
                        ?? capturedResult.dbhInches
        let heightValue  = parseFeet(heightFeetText.trimmingCharacters(in: .whitespaces))
                        ?? capturedResult.heightFeet
        let spread1Value = parseFeet(spread1FeetText.trimmingCharacters(in: .whitespaces))
                        ?? capturedResult.spread1Feet
        let spread2Value = parseFeet(spread2FeetText.trimmingCharacters(in: .whitespaces))
                        ?? capturedResult.spread2Feet

        // treeType is kept in sync with DBH (manual entry above, AR result on capture)
        // and remains overridable via the Tree Type picker on the Details step.
        let derivedType = treeType

        let resolvedSiteCode = project.siteCodes.isEmpty ? siteCodeText : selectedSiteCode

        // GPS
        let lat  = location.location?.coordinate.latitude  ?? 0
        let lon  = location.location?.coordinate.longitude ?? 0
        let acc  = location.location?.horizontalAccuracy   ?? 0
        let utm  = UTMConverter.convert(latitude: lat, longitude: lon)

        let record = TreeRecord(
            project: project,
            surveyorName: surveyorName.trimmingCharacters(in: .whitespaces),
            deviceId: DeviceID.current,
            timestamp: Date(),
            latitude: lat,
            longitude: lon,
            gpsAccuracy: acc,
            utmNorthing: utm.northing,
            utmEasting: utm.easting,
            utmZone: utm.zone,
            siteCode: resolvedSiteCode,
            treeId: treeId.trimmingCharacters(in: .whitespaces),
            dbhInches: dbhValue,
            heightFeet: heightValue,
            spread1Feet: spread1Value,
            spread2Feet: spread2Value,
            treeType: derivedType,
            isMultiBranch: isMultiBranch,
            condition: condition,
            species: species.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces),
            photoURL: photoFilename,
            pointCloudSliceRef: capturedResult.pointCloudSliceRef
        )

        modelContext.insert(record)
        dismiss()
    }
}

// MARK: - Step Progress View

struct StepProgressView: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { i in
                    Capsule()
                        .fill(i <= current ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                        .animation(.easeInOut, value: current)
                }
            }
            Text("Step \(current) of \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, TreeRecord.self, configurations: config)
    let project = Project(name: "City Park", siteCodes: ["A1", "B2"])
    container.mainContext.insert(project)
    return CaptureView(project: project)
        .modelContainer(container)
}
