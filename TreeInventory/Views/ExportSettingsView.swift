//
//  ExportSettingsView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData
import UIKit

struct ExportSettingsView: View {
    @AppStorage("surveyorName") private var surveyorName: String = ""
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProject: Project?
    @State private var showingAddProject = false
    @State private var showingSyncAlert = false
    @State private var exportAlert: ExportAlert? = nil
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // Surveyor section
                Section("Surveyor") {
                    TextField("Your name", text: $surveyorName)
                        .autocorrectionDisabled()
                }

                // Export section
                Section("Export") {
                    Picker("Project", selection: $selectedProject) {
                        Text("Select a project").tag(Optional<Project>.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }

                    Button {
                        exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(selectedProject == nil)
                }

                // Projects section
                Section("Projects") {
                    ForEach(projects) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.headline)
                                Text("\(project.treeRecords.count) tree\(project.treeRecords.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showingAddProject = true
                    } label: {
                        Label("Add Project", systemImage: "plus.circle")
                    }
                }

                // Sync section
                Section("Sync") {
                    Button {
                        showingSyncAlert = true
                    } label: {
                        Label("Sync with Supabase", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .navigationTitle("Export & Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddProject) {
                AddProjectView()
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            .alert("Sync", isPresented: $showingSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Supabase not configured. Add credentials in a future update.")
            }
            .alert(item: $exportAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message))
            }
        }
    }

    private func exportCSV() {
        guard let project = selectedProject else { return }

        // TODO: import CSVExporter from TreeInventory/Export/CSVExporter.swift
        // When CSVExporter is available, replace this stub with:
        // let csv = CSVExporter.export(project: project)
        let csvHeader = "ec5_uuid,created_at,title,site_code,tree_id,surveyor_name,device_id,uploaded_at,latitude,longitude,gps_accuracy,utm_northing,utm_easting,utm_zone,dbh_inches,height_feet,spread1_feet,spread2_feet,tree_type,is_multi_branch,condition,species,notes,photo_url\n"
        let csvRows = project.treeRecords.map { r -> String in
            let vals: [String] = [
                r.id.uuidString,
                ISO8601DateFormatter().string(from: r.timestamp),
                r.treeId,
                r.siteCode,
                r.treeId,
                r.surveyorName,
                r.deviceId,
                r.uploadedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                String(r.latitude),
                String(r.longitude),
                String(r.gpsAccuracy),
                String(r.utmNorthing),
                String(r.utmEasting),
                r.utmZone,
                r.dbhInches.map { String($0) } ?? "",
                r.heightFeet.map { String($0) } ?? "",
                r.spread1Feet.map { String($0) } ?? "",
                r.spread2Feet.map { String($0) } ?? "",
                r.treeType.rawValue,
                r.isMultiBranch ? "true" : "false",
                r.condition.rawValue,
                r.species,
                r.notes.replacingOccurrences(of: ",", with: ";"),
                r.photoURL ?? ""
            ]
            return vals.joined(separator: ",")
        }.joined(separator: "\n")

        let csv = csvHeader + csvRows

        let fileName = "\(project.name.replacingOccurrences(of: " ", with: "_"))_export.csv"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tmpURL, atomically: true, encoding: .utf8)
            shareItems = [tmpURL]
            showingShareSheet = true
        } catch {
            exportAlert = ExportAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Helpers

struct ExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportSettingsView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
