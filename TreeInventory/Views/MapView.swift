//
//  MapView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//
//  Interactive MapKit view: every tree in the selected project is plotted
//  as a pin (colored by condition), and tapping a pin shows a quick-look
//  card with a link into the existing TreeDetailView.
//

import SwiftUI
import SwiftData
import MapKit

struct MapView: View {
    @Query private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRecord: TreeRecord?

    private var records: [TreeRecord] {
        guard let project = selectedProject else { return [] }
        // Skip records that never got a real GPS fix (lat/long both 0).
        return project.treeRecords.filter { $0.latitude != 0 || $0.longitude != 0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                } else if records.isEmpty {
                    ContentUnavailableView(
                        "No Trees",
                        systemImage: "leaf.circle",
                        description: Text("This project has no trees with a GPS location yet.")
                    )
                } else {
                    Map(position: $cameraPosition) {
                        ForEach(records) { record in
                            Annotation(
                                record.treeId.isEmpty ? "Tree" : record.treeId,
                                coordinate: record.coordinate,
                                anchor: .bottom
                            ) {
                                TreePinView(record: record)
                                    .onTapGesture { selectedRecord = record }
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                        MapUserLocationButton()
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: selectedProject) { _, _ in fitCamera() }
            .onAppear {
                if selectedProject == nil { selectedProject = projects.first }
                fitCamera()
            }
            .sheet(item: $selectedRecord) { record in
                TreePinDetailSheet(record: record)
                    .presentationDetents([.height(260), .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func fitCamera() {
        guard !records.isEmpty else {
            cameraPosition = .automatic
            return
        }
        let lats = records.map(\.latitude)
        let lons = records.map(\.longitude)
        guard
            let minLat = lats.min(), let maxLat = lats.max(),
            let minLon = lons.min(), let maxLon = lons.max()
        else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.004)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Pin

private struct TreePinView: View {
    let record: TreeRecord

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(record.condition.color)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
            Triangle()
                .fill(record.condition.color)
                .frame(width: 10, height: 6)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Quick-look sheet

private struct TreePinDetailSheet: View {
    let record: TreeRecord

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TreeCardView(record: record)

                HStack(spacing: 16) {
                    Label(record.dbhInches.map { String(format: "DBH %.1f in", $0) } ?? "DBH —", systemImage: "circle.dashed")
                    Label(record.heightFeet.map { String(format: "H %.1f ft", $0) } ?? "H —", systemImage: "arrow.up.to.line")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                NavigationLink {
                    TreeDetailView(record: record)
                } label: {
                    Label("View Full Details", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle(record.treeId.isEmpty ? "(no ID)" : record.treeId)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Coordinate helper

extension TreeRecord {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview {
    MapView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
