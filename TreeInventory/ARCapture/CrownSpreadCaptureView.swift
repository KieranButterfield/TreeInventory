//
//  CrownSpreadCaptureView.swift
//  TreeInventory
//
//  Two-tap AR ruler repeated twice for crown spread measurement.
//
//  Each measurement:
//    • First tap  → anchors point A
//    • Second tap → anchors point B; computes Euclidean distance converted to feet
//  This is repeated for spread1 and spread2.
//  Both measurements shown; "Done" calls onComplete.
//

import SwiftUI
import ARKit
import SceneKit

// MARK: - SwiftUI view

/// Two-round AR tap-to-measure view for crown spread.
struct CrownSpreadCaptureView: View {

    var onComplete: (CaptureResult) -> Void

    // MARK: - State

    @State private var spread1Feet: Double? = nil
    @State private var spread2Feet: Double? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            SpreadARContainer(
                spread1Feet: $spread1Feet,
                spread2Feet: $spread2Feet
            )
            .ignoresSafeArea()

            bottomPanel
        }
        .navigationTitle("Crown Spread")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 8) {
            instructionBanner
            measurementDisplay
        }
        .padding(.bottom, 8)
    }

    private var instructionBanner: some View {
        let msg: String
        if spread1Feet == nil {
            msg = "Tap one edge of the crown (spread 1 — point A)"
        } else if spread2Feet == nil && spread1Feet != nil {
            // We know spread1 is underway or done; the coordinator handles
            // which tap within spread1/spread2 is expected.
            msg = "Tap to complete measurement"
        } else {
            msg = "Both spreads measured — tap Done"
        }
        return Text(msg)
            .font(.subheadline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var measurementDisplay: some View {
        HStack(spacing: 20) {
            measurementCell(label: "Spread 1", value: spread1Feet)
            measurementCell(label: "Spread 2", value: spread2Feet)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

        if spread1Feet != nil && spread2Feet != nil {
            Button("Done") {
                onComplete(CaptureResult(
                    spread1Feet: spread1Feet,
                    spread2Feet: spread2Feet
                ))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func measurementCell(label: String, value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let v = value {
                Text(String(format: "%.1f ft", v))
                    .font(.title3.monospacedDigit().bold())
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - AR container (UIViewRepresentable)

private struct SpreadARContainer: UIViewRepresentable {

    @Binding var spread1Feet: Double?
    @Binding var spread2Feet: Double?

    func makeCoordinator() -> SpreadCoordinator {
        SpreadCoordinator(
            spread1Binding: $spread1Feet,
            spread2Binding: $spread2Feet
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.autoenablesDefaultLighting = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(SpreadCoordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        context.coordinator.sceneView = view
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: SpreadCoordinator) {
        coordinator.stopSession()
    }
}

// MARK: - Coordinator

@MainActor
final class SpreadCoordinator: NSObject {

    weak var sceneView: ARSCNView?

    // Bindings back to SwiftUI
    private var spread1Binding: Binding<Double?>
    private var spread2Binding: Binding<Double?>

    // Tap-state machine:
    // phase 0: waiting for spread-1 point A
    // phase 1: waiting for spread-1 point B
    // phase 2: waiting for spread-2 point A
    // phase 3: waiting for spread-2 point B
    // phase 4: done
    private var phase = 0
    private var pointA: SIMD3<Float>? = nil

    // Visual anchor nodes
    private var markerNodes: [SCNNode] = []
    private var lineNodes:   [SCNNode] = []

    init(spread1Binding: Binding<Double?>, spread2Binding: Binding<Double?>) {
        self.spread1Binding = spread1Binding
        self.spread2Binding = spread2Binding
    }

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        // Plane detection helps with floor / ground raycasting.
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        sceneView?.session.pause()
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard phase < 4, let sceneView else { return }
        let location = gesture.location(in: sceneView)

        // Try mesh raycast first, fall back to estimated plane.
        let worldPos: SIMD3<Float>?
        if let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any),
           let hit = sceneView.session.raycast(query).first {
            let col = hit.worldTransform.columns.3
            worldPos = SIMD3(col.x, col.y, col.z)
        } else if let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any),
                  let hit = sceneView.session.raycast(query).first {
            let col = hit.worldTransform.columns.3
            worldPos = SIMD3(col.x, col.y, col.z)
        } else {
            worldPos = nil
        }

        guard let pos = worldPos else { return }

        switch phase {
        case 0, 2:
            // Point A of a new measurement.
            pointA = pos
            placeMarker(at: pos, color: .systemBlue)
            phase += 1

        case 1, 3:
            // Point B — compute distance.
            guard let a = pointA else { return }
            let b = pos
            let diff = b - a
            let distMetres = sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
            let distFeet = Double(distMetres) * 3.28084

            placeMarker(at: b, color: .systemOrange)
            drawLine(from: a, to: b)

            if phase == 1 {
                spread1Binding.wrappedValue = distFeet
            } else {
                spread2Binding.wrappedValue = distFeet
            }

            pointA = nil
            phase += 1

        default:
            break
        }
    }

    // MARK: - AR Markers & Lines

    private func placeMarker(at pos: SIMD3<Float>, color: UIColor) {
        guard let sceneView else { return }
        let sphere = SCNSphere(radius: 0.03)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.9)
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        sceneView.scene.rootNode.addChildNode(node)
        markerNodes.append(node)
    }

    private func drawLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        guard let sceneView else { return }

        // Build a thin box oriented between the two points.
        let diff = b - a
        let length = Double(sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z))
        guard length > 0 else { return }

        let box = SCNBox(width: CGFloat(length), height: 0.01, length: 0.01, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.8)
        box.materials = [mat]

        let node = SCNNode(geometry: box)

        // Position at midpoint.
        let mid = (a + b) * 0.5
        node.position = SCNVector3(mid.x, mid.y, mid.z)

        // Orient along the diff vector.
        let dir = SIMD3<Float>(diff.x, diff.y, diff.z) / Float(length)
        let xAxis = SIMD3<Float>(1, 0, 0)
        let cross = simd_cross(xAxis, dir)
        let dot   = simd_dot(xAxis, dir)
        if simd_length(cross) < 1e-6 {
            // Vectors are parallel.
            if dot < 0 { node.eulerAngles = SCNVector3(0, Float.pi, 0) }
        } else {
            let angle = acos(min(max(dot, -1), 1))
            let axis  = simd_normalize(cross)
            node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        }

        sceneView.scene.rootNode.addChildNode(node)
        lineNodes.append(node)
    }
}
