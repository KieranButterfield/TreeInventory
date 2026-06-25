//
//  ProjectsView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddProject = false

    var body: some View {
        NavigationStack {
            List(projects) { project in
                NavigationLink(destination: ProjectTreeListView(project: project)) {
                    ProjectRowView(project: project)
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectView()
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "tree.circle",
                        description: Text("Tap + to create your first project.")
                    )
                }
            }
        }
    }
}

struct ProjectRowView: View {
    let project: Project

    private var goodCount: Int { project.treeRecords.filter { $0.condition == .good }.count }
    private var fairCount: Int { project.treeRecords.filter { $0.condition == .fair }.count }
    private var poorCount: Int { project.treeRecords.filter { $0.condition == .poor }.count }
    private var totalCount: Int { project.treeRecords.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.headline)

            HStack(spacing: 8) {
                ConditionPill(count: goodCount, condition: .good)
                ConditionPill(count: fairCount, condition: .fair)
                ConditionPill(count: poorCount, condition: .poor)
                Spacer()
                Text("\(totalCount) tree\(totalCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConditionPill: View {
    let count: Int
    let condition: TreeCondition

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(condition.color)
                .frame(width: 8, height: 8)
            Text("\(count) \(condition.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(condition.color.opacity(0.12), in: Capsule())
    }
}

#Preview {
    ProjectsView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
