//
//  TreeCardView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI

struct TreeCardView: View {
    let record: TreeRecord

    private var dbhText: String {
        if let dbh = record.dbhInches {
            return String(format: "%.1f in", dbh)
        }
        return "—"
    }

    private var heightText: String {
        if let h = record.heightFeet {
            return formatFeetInches(h)
        }
        return "—"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 3)
                .fill(record.condition.color)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(record.treeId.isEmpty ? "(no ID)" : record.treeId)
                                .font(.headline)
                            if !record.siteCode.isEmpty {
                                Text(record.siteCode)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Condition pill
                        HStack(spacing: 3) {
                            Circle()
                                .fill(record.condition.color)
                                .frame(width: 7, height: 7)
                            Text(record.condition.label)
                                .font(.caption)
                                .foregroundStyle(record.condition.color)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(record.condition.color.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    // Multi-branch badge
                    if record.isMultiBranch {
                        Text("multi-branch")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange, in: Capsule())
                    }
                }

                // Measurements row
                HStack(spacing: 16) {
                    Label("DBH: \(dbhText)", systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("H: \(heightText)", systemImage: "arrow.up.to.line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Footer: timestamp + surveyor
                HStack {
                    Text(record.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !record.surveyorName.isEmpty {
                        Label(record.surveyorName, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 10)
            .padding(.trailing, 8)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}
