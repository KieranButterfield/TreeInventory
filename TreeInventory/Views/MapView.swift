//
//  MapView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct MapView: View {
    @Query private var projects: [Project]
    @State private var selectedProject: Project?

    private var recordsByCode: [(String, [TreeRecord])] {
        guard let project = selectedProject else { return [] }
        let sorted = project.treeRecords.sorted { $0.siteCode < $1.siteCode }
        var grouped: [(String, [TreeRecord])] = []
        var current: (String, [TreeRecord])? = nil
        for record in sorted {
            if current?.0 == record.siteCode {
                current!.1.append(record)
            } else {
                if let prev = current { grouped.append(prev) }
                current = (record.siteCode, [record])
            }
        }
        if let last = current { grouped.append(last) }
        return grouped
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Interactive map placeholder
                Text("// Interactive map pins coming in a later phase.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary)

                // Project picker
                Picker("Project", selection: $selectedProject) {
                    Text("Select a project").tag(Optional<Project>.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if selectedProject == nil {
                    ContentUnavailableView(
                        "No Project Selected",
                        systemImage: "map",
                        description: Text("Choose a project to view its trees.")
                    )
                } else if recordsByCode.isEmpty {
                    ContentUnavailableView(
                        "No Trees",
                        systemImage: "leaf.circle",
                        description: Text("This project has no recorded trees.")
                    )
                } else {
                    List {
                        ForEach(recordsByCode, id: \.0) { code, records in
                            Section(header: Text(code.isEmpty ? "No Site Code" : code)) {
                                ForEach(records) { record in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(record.treeId.isEmpty ? "(no ID)" : record.treeId)
                                                .font(.headline)
                                            Spacer()
                                            if let dbh = record.dbhInches {
                                                Text(String(format: "DBH %.1f in", dbh))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Text(String(format: "%.6f, %.6f", record.latitude, record.longitude))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    MapView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
