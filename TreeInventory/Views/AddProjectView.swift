//
//  AddProjectView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct AddProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var siteCodesText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Project name", text: $projectName)
                }
                Section {
                    TextField("Site codes (comma-separated)", text: $siteCodesText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Site Codes")
                } footer: {
                    Text("Example: A1, B2, C3")
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProject()
                    }
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addProject() {
        let codes = siteCodesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let project = Project(
            name: projectName.trimmingCharacters(in: .whitespaces),
            siteCodes: codes
        )
        modelContext.insert(project)
        dismiss()
    }
}

#Preview {
    AddProjectView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
