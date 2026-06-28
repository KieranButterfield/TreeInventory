//
//  CrownSpreadCaptureView.swift
//  TreeInventory
//
//  Two-tap AR ruler repeated twice for crown spread measurement.
//
//  Each measurement:
//    • First tap  → anchors point A
//    • Second tap → anchors point B; computes Euclidean distance converted to feet
//  This is repeated for spread1 and spread2. Either spread can be redone
//  independently without disturbing the other. Both measurements shown;
//  "Done" calls onComplete.
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
    @State private var coordinatorRef: SpreadCoordinator? = nil
    @State private var tapHint: String? = nil
    @State private var hintDismissTask: Task<Void, Never>? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            SpreadARContainer(
                spread1Feet: $spread1Feet,
                spread2Feet: $spread2Feet,
                onCoordinatorReady: { coordinatorRef = $0 },
                onTapFailed: { reason in showTapHint(reason) }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                if let tapHint {
                    tapHintBanner(tapHint)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                bottomPanel
            }
            .animation(.easeInOut(duration: 0.2), value: tapHint)
        }
        .navigationTitle("Crown Spread")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tap feedback

    /// Shows a brief on-screen reason when a tap doesn't register or gets
    /// rejected (e.g. it likely landed on a different tree or the ground far
    /// behind the canopy), so the surveyor isn't tapping blindly.
    private func showTapHint(_ reason: String) {
        tapHint = reason
        hintDismissTask?.cancel()
        hintDismissTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { tapHint = nil }
        }
    }

    private func tapHintBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 16)
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
            msg = "Tap one edge of the crown, then the opposite edge (spread 1)"
        } else if spread2Feet == nil {
            msg = "Now tap one edge, then the opposite edge for spread 2 (rotate ~90°)"
        } else {
            msg = "Both spreads measured — tap Done, or Redo either one"
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
            measurementCell(label: "Spread 1", value: spread1Feet) {
                coordinatorRef?.redo(spread: 1)
            }
            measurementCell(label: "Spread 2", value: spread2Feet) {
                coordinatorRef?.redo(spread: 2)
            }
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
    private func measurementCell(label: String, value: Double?, onRedo: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let v = value {
                Text(String(format: "%.1f ft", v))
                    .font(.title3.monospacedDigit().bold())
                Button("Redo", action: onRedo)
                    .font(.caption2)
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 80)
    }
}

// MARK: - AR container (UIViewRepresentable)

private struct SpreadARContainer: UIViewRepresentable {

    @Binding var spread1Feet: Double?
    @Binding var spread2Feet: Double?
    var onCoordinatorReady: (SpreadCoordinator) -> Void = { _ in }
    var onTapFailed: (String) -> Void = { _ in }

    func makeCoordinator() -> SpreadCoordinator {
        SpreadCoordinator(
            spread1Binding: $spread1Feet,
            spread2Binding: $spread2Feet,
            onTapFailed: onTapFailed
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
        onCoordinatorReady(context.coordinator)
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
    private let onTapFailed: (String) -> Void

    /// Which spread the next pair of taps fills in. 0 means both are done
    /// and no redo is in progress (taps are ignored until Redo is tapped).
    private var activeSpread: Int = 1
    private var pointA: SIMD3<Float>? = nil
    /// Distance from the camera to pointA, used to sanity-check point B.
    private var pointADistance: Float? = nil

    // Visual anchor nodes, tracked per spread so a redo only clears that
    // spread's markers/line.
    private var spread1Nodes: [SCNNode] = []
    private var spread2Nodes: [SCNNode] = []

    /// Raycast hits farther than this from the camera are rejected outright —
    /// catches taps that "jumped" through a canopy gap onto the ground or a
    /// tree far behind the subject tree.
    private let maxPlausibleDistance: Float = 15.0   // meters (~49 ft)
    /// If point B's distance from the camera differs from point A's by more
    /// than this, it likely landed on a different object than point A did.
    private let maxPairDistanceDelta: Float = 6.0    // meters (~20 ft)

    init(spread1Binding: Binding<Double?>, spread2Binding: Binding<Double?>, onTapFailed: @escaping (String) -> Void = { _ in }) {
        self.spread1Binding = spread1Binding
        self.spread2Binding = spread2Binding
        self.onTapFailed = onTapFailed
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

    /// Restarts capture for one spread (1 or 2) without disturbing the other.
    func redo(spread: Int) {
        guard spread == 1 || spread == 2 else { return }
        clearNodes(for: spread)
        if spread == 1 {
            spread1Binding.wrappedValue = nil
        } else {
            spread2Binding.wrappedValue = nil
        }
        pointA = nil
        pointADistance = nil
        activeSpread = spread
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard activeSpread != 0, let sceneView else { return }
        let location = gesture.location(in: sceneView)

        // Try mesh raycast first, fall back to estimated plane.
        var hitResult: ARRaycastResult? = nil
        if let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any) {
            hitResult = sceneView.session.raycast(query).first
        }
        if hitResult == nil, let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
            hitResult = sceneView.session.raycast(query).first
        }

        guard let result = hitResult,
              let cameraTransform = sceneView.session.currentFrame?.camera.transform
        else {
            onTapFailed("No surface detected there. Move slightly closer and try again.")
            return
        }

        let col = result.worldTransform.columns.3
        let pos = SIMD3<Float>(col.x, col.y, col.z)
        let camCol = cameraTransform.columns.3
        let camPos = SIMD3<Float>(camCol.x, camCol.y, camCol.z)
        let distFromCamera = simd_length(pos - camPos)

        // Reject hits that are implausibly far away — almost always means the
        // tap "jumped" through a gap in the canopy onto the ground or another
        // tree behind the subject.
        guard distFromCamera <= maxPlausibleDistance else {
            onTapFailed("That tap landed unexpectedly far away — probably a different tree or the ground behind it. Try tapping a clearer, closer edge of this tree's canopy.")
            return
        }

        if let a = pointA, let aDist = pointADistance {
            // This tap is point B of the current pair.
            let delta = abs(distFromCamera - aDist)
            guard delta <= maxPairDistanceDelta else {
                onTapFailed("That second tap landed much farther or closer than the first one — it likely hit a different tree. Try tapping the matching edge of the same canopy.")
                return
            }

            let diff = pos - a
            let distMetres = Double(simd_length(diff))
            // LiDAR mesh typically doesn't reach the outermost canopy edge,
            // so taps land slightly inside the true drip line. Empirically
            // calibrated at 1.20 (20%) — adjust if field testing shows over/under.
            let distFeet = distMetres * 3.28084 * 1.20

            placeMarker(at: pos, color: .systemOrange, spread: activeSpread)
            drawLine(from: a, to: pos, spread: activeSpread)

            if activeSpread == 1 {
                spread1Binding.wrappedValue = distFeet
            } else {
                spread2Binding.wrappedValue = distFeet
            }

            pointA = nil
            pointADistance = nil

            // Advance to whichever spread still needs capturing, or finish.
            if activeSpread == 1 && spread2Binding.wrappedValue == nil {
                activeSpread = 2
            } else if activeSpread == 2 && spread1Binding.wrappedValue == nil {
                activeSpread = 1
            } else {
                activeSpread = 0
            }
        } else {
            // This tap is point A of a new pair.
            pointA = pos
            pointADistance = distFromCamera
            placeMarker(at: pos, color: .systemBlue, spread: activeSpread)
        }
    }

    // MARK: - AR Markers & Lines

    private func placeMarker(at pos: SIMD3<Float>, color: UIColor, spread: Int) {
        guard let sceneView else { return }
        let sphere = SCNSphere(radius: 0.03)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.9)
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        sceneView.scene.rootNode.addChildNode(node)
        if spread == 1 { spread1Nodes.append(node) } else { spread2Nodes.append(node) }
    }

    private func drawLine(from a: SIMD3<Float>, to b: SIMD3<Float>, spread: Int) {
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
        if spread == 1 { spread1Nodes.append(node) } else { spread2Nodes.append(node) }
    }

    private func clearNodes(for spread: Int) {
        if spread == 1 {
            spread1Nodes.forEach { $0.removeFromParentNode() }
            spread1Nodes.removeAll()
        } else {
            spread2Nodes.forEach { $0.removeFromParentNode() }
            spread2Nodes.removeAll()
        }
    }
}
