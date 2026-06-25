//
//  CaptureView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData
import UIKit

struct CaptureView: View {
    let project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 1

    // Step 1 — Height
    @State private var heightFeetText: String = ""

    // Step 2 — DBH
    @State private var dbhInchesText: String = ""

    // Step 3 — Crown Spread
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

    private let totalSteps = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                StepProgressView(current: step, total: totalSteps)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch step {
                        case 1:
                            heightStepView
                        case 2:
                            dbhStepView
                        case 3:
                            crownSpreadStepView
                        case 4:
                            detailsStepView
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }

                Divider()

                // Navigation buttons
                HStack {
                    if step > 1 {
                        Button("Back") {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if step < totalSteps {
                        Button("Next") {
                            withAnimation { step += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Save") {
                            saveRecord()
                        }
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
        }
        .onAppear {
            if let first = project.siteCodes.first {
                selectedSiteCode = first
            }
            // Auto-set treeType hint from DBH
        }
    }

    // MARK: - Step Views

    private var heightStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Height Measurement", systemImage: "arrow.up.to.line")
                .font(.title2.bold())

            Text("Stand back from the tree and enter the horizontal distance, then sight the base and top.")
                .foregroundStyle(.secondary)

            // TODO: plug in HeightCaptureView from ARCapture module
            VStack(alignment: .leading, spacing: 8) {
                Text("Height (ft)")
                    .font(.subheadline.bold())
                TextField("e.g. 45.0", text: $heightFeetText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            Text("AR-assisted height capture will be available once the ARCapture module is integrated.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    private var dbhStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("DBH Measurement", systemImage: "circle.dashed")
                .font(.title2.bold())

            Text("Walk to the trunk. Tap the trunk at breast height (4'4\").")
                .foregroundStyle(.secondary)

            // TODO: plug in DBHCaptureView from ARCapture module
            VStack(alignment: .leading, spacing: 8) {
                Text("DBH circumference (in)")
                    .font(.subheadline.bold())
                TextField("e.g. 12.5", text: $dbhInchesText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            Text("AR-assisted DBH capture will be available once the ARCapture module is integrated.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    private var crownSpreadStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Crown Spread", systemImage: "arrow.left.and.right")
                .font(.title2.bold())

            Text("Walk to the canopy edge. Take two perpendicular measurements.")
                .foregroundStyle(.secondary)

            // TODO: plug in CrownSpreadCaptureView from ARCapture module
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spread 1 (ft)")
                        .font(.subheadline.bold())
                    TextField("e.g. 18.0", text: $spread1FeetText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Spread 2 (ft)")
                        .font(.subheadline.bold())
                    TextField("e.g. 20.0", text: $spread2FeetText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("AR-assisted crown spread capture will be available once the ARCapture module is integrated.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    private var detailsStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Tree Details", systemImage: "doc.text")
                .font(.title2.bold())

            // Tree ID
            VStack(alignment: .leading, spacing: 6) {
                Text("Tree ID")
                    .font(.subheadline.bold())
                TextField("e.g. T-001", text: $treeId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            // Site Code
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

            // Condition
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

            // Tree Type
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tree Type")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("(auto-set from DBH ≥ 20)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Tree Type", selection: $treeType) {
                    Text("Large Mature").tag(TreeType.largeMatureTree)
                    Text("Young").tag(TreeType.youngTree)
                    Text("Newly Planted").tag(TreeType.newlyPlantedTree)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Multi-branch
            Toggle("Multi-branch", isOn: $isMultiBranch)
                .font(.subheadline.bold())

            // Species
            VStack(alignment: .leading, spacing: 6) {
                Text("Species")
                    .font(.subheadline.bold())
                TextField("e.g. Quercus robur", text: $species)
                    .textFieldStyle(.roundedBorder)
            }

            // Notes
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
        }
    }

    // MARK: - Save

    private func saveRecord() {
        let dbhValue: Double? = Double(dbhInchesText.trimmingCharacters(in: .whitespaces))
        let heightValue: Double? = Double(heightFeetText.trimmingCharacters(in: .whitespaces))
        let spread1Value: Double? = Double(spread1FeetText.trimmingCharacters(in: .whitespaces))
        let spread2Value: Double? = Double(spread2FeetText.trimmingCharacters(in: .whitespaces))

        // Auto-set treeType based on DBH
        let derivedTreeType: TreeType
        if let dbh = dbhValue, dbh >= 20 {
            derivedTreeType = .largeMatureTree
        } else {
            derivedTreeType = treeType
        }

        let resolvedSiteCode = project.siteCodes.isEmpty ? siteCodeText : selectedSiteCode

        let record = TreeRecord(
            project: project,
            surveyorName: UserDefaults.standard.string(forKey: "surveyorName") ?? "",
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "",
            timestamp: Date(),
            siteCode: resolvedSiteCode,
            treeId: treeId.trimmingCharacters(in: .whitespaces),
            dbhInches: dbhValue,
            heightFeet: heightValue,
            spread1Feet: spread1Value,
            spread2Feet: spread2Value,
            treeType: derivedTreeType,
            isMultiBranch: isMultiBranch,
            condition: condition,
            species: species.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
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
