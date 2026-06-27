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
    @AppStorage("supabaseURL") private var supabaseURL: String = ""
    @AppStorage("supabaseAnonKey") private var supabaseAnonKey: String = ""
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProject: Project?
    @State private var showingAddProject = false
    @State private var activeAlert: AppAlert? = nil
    @State private var isSyncing = false
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    private enum ConnectionStatus: Equatable {
        case unknown
        case success
        case failure(String)
    }

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

                // Supabase configuration
                Section {
                    TextField("Project URL (https://xxxx.supabase.co)", text: $supabaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Anon key", text: $supabaseAnonKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        testConnection()
                    } label: {
                        if isTestingConnection {
                            HStack {
                                ProgressView()
                                Text("Testing…")
                            }
                        } else {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .disabled(supabaseURL.isEmpty || supabaseAnonKey.isEmpty || isTestingConnection)

                    connectionStatusRow
                } header: {
                    Text("Supabase")
                } footer: {
                    Text("Found in your Supabase project under Settings > API. The anon key is meant to be embedded in client apps — it's safe to store here.")
                }

                // Sync section
                Section {
                    Button {
                        syncSelectedProject()
                    } label: {
                        if isSyncing {
                            HStack {
                                ProgressView()
                                Text("Syncing…")
                            }
                        } else {
                            Label("Sync with Supabase", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(selectedProject == nil || isSyncing)
                } footer: {
                    Text("Uploads the selected project and its tree records. Re-syncing updates existing rows instead of duplicating them.")
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
            .onChange(of: supabaseURL) { _, _ in connectionStatus = .unknown }
            .onChange(of: supabaseAnonKey) { _, _ in connectionStatus = .unknown }
            .alert(item: $activeAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message))
            }
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch connectionStatus {
        case .unknown:
            EmptyView()
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func exportCSV() {
        guard let project = selectedProject else { return }
        do {
            let url = try CSVExporter.temporaryFileURL(for: project.treeRecords, projectName: project.name)
            shareItems = [url]
            showingShareSheet = true
        } catch {
            activeAlert = AppAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Supabase sync

    private func testConnection() {
        isTestingConnection = true
        Task {
            await SupabaseClient.shared.configure(url: supabaseURL, anonKey: supabaseAnonKey)
            do {
                try await SupabaseClient.shared.testConnection()
                connectionStatus = .success
            } catch {
                connectionStatus = .failure(error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    private func syncSelectedProject() {
        guard let project = selectedProject else { return }
        isSyncing = true
        Task {
            await SupabaseClient.shared.configure(url: supabaseURL, anonKey: supabaseAnonKey)
            do {
                try await SupabaseClient.shared.uploadProject(SupabaseProjectPayload(project: project))

                var uploadedCount = 0
                var failedCount = 0
                let now = Date()
                for record in project.treeRecords {
                    do {
                        try await SupabaseClient.shared.uploadRecord(SupabaseTreeRecordPayload(record: record))
                        record.uploadedAt = now
                        uploadedCount += 1
                    } catch {
                        failedCount += 1
                    }
                }
                try? modelContext.save()

                let message: String
                if failedCount == 0 {
                    message = "Uploaded \(uploadedCount) tree record\(uploadedCount == 1 ? "" : "s")."
                } else {
                    message = "Uploaded \(uploadedCount), failed \(failedCount). Try syncing again to retry the failed records."
                }
                activeAlert = AppAlert(title: "Sync Complete", message: message)
            } catch {
                activeAlert = AppAlert(title: "Sync Failed", message: error.localizedDescription)
            }
            isSyncing = false
        }
    }
}

// MARK: - Helpers

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ExportSettingsView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
