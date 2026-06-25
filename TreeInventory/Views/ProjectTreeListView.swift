//
//  ProjectTreeListView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct ProjectTreeListView: View {
    let project: Project
    @State private var showingCapture = false

    private var goodCount: Int { project.treeRecords.filter { $0.condition == .good }.count }
    private var fairCount: Int { project.treeRecords.filter { $0.condition == .fair }.count }
    private var poorCount: Int { project.treeRecords.filter { $0.condition == .poor }.count }

    var body: some View {
        List {
            // Condition summary header
            Section {
                HStack(spacing: 10) {
                    ConditionPill(count: goodCount, condition: .good)
                    ConditionPill(count: fairCount, condition: .fair)
                    ConditionPill(count: poorCount, condition: .poor)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // Tree records
            ForEach(project.treeRecords.sorted(by: { $0.timestamp > $1.timestamp })) { record in
                NavigationLink(destination: TreeDetailView(record: record)) {
                    TreeCardView(record: record)
                        .listRowBackground(Color.clear)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCapture = true
                } label: {
                    Label("Measure", systemImage: "leaf.fill")
                }
            }
        }
        .sheet(isPresented: $showingCapture) {
            CaptureView(project: project)
        }
        .overlay {
            if project.treeRecords.isEmpty {
                ContentUnavailableView(
                    "No Trees",
                    systemImage: "leaf.circle",
                    description: Text("Tap Measure to record your first tree.")
                )
            }
        }
    }
}
