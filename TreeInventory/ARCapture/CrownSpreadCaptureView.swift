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
                Text(formatFeetInches(v))
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

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(SpreadCoordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

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

    private var spread1Binding: Binding<Double?>
    private var spread2Binding: Binding<Double?>
    private let onTapFailed: (String) -> Void

    /// Which spread the next pair of taps fills in. 0 = both done, taps ignored.
    private var activeSpread: Int = 1
    /// Ephemeral first-tap position while waiting for the second tap.
    private var pointA: SIMD3<Float>? = nil
    private var pointADistance: Float? = nil

    // Named marker nodes — one per endpoint so drag can reference them directly.
    private var spread1MarkerA: SCNNode? = nil   // blue dot, spread 1
    private var spread1MarkerB: SCNNode? = nil   // orange dot, spread 1
    private var spread2MarkerA: SCNNode? = nil
    private var spread2MarkerB: SCNNode? = nil

    // Line nodes kept separately so drag can replace them without touching markers.
    private var spread1LineNode: SCNNode? = nil
    private var spread2LineNode: SCNNode? = nil

    // World positions retained so the line can be redrawn when a dot is dragged.
    private var spread1A: SIMD3<Float>? = nil
    private var spread1B: SIMD3<Float>? = nil
    private var spread2A: SIMD3<Float>? = nil
    private var spread2B: SIMD3<Float>? = nil

    // Drag state
    private var draggingNode: SCNNode? = nil
    private var draggingIsA: Bool = false
    private var draggingSpread: Int = 0

    private let maxPlausibleDistance: Float = 15.0
    private let maxPairDistanceDelta: Float = 6.0

    init(spread1Binding: Binding<Double?>, spread2Binding: Binding<Double?>, onTapFailed: @escaping (String) -> Void = { _ in }) {
        self.spread1Binding = spread1Binding
        self.spread2Binding = spread2Binding
        self.onTapFailed = onTapFailed
    }

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        sceneView?.session.pause()
    }

    func redo(spread: Int) {
        guard spread == 1 || spread == 2 else { return }
        clearNodes(for: spread)
        if spread == 1 {
            spread1Binding.wrappedValue = nil
            spread1A = nil; spread1B = nil
        } else {
            spread2Binding.wrappedValue = nil
            spread2A = nil; spread2B = nil
        }
        pointA = nil
        pointADistance = nil
        activeSpread = spread
    }

    // MARK: - Tap handling

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard activeSpread != 0, let sceneView else { return }
        let location = gesture.location(in: sceneView)

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

        // Reject hits on vertical planes (walls, fences) — canopy edges in open
        // space should never hit a purely vertical surface.
        if result.targetAlignment == .vertical {
            onTapFailed("That hit a wall — try tapping the canopy edge from a different angle.")
            return
        }

        let col = result.worldTransform.columns.3
        let pos = SIMD3<Float>(col.x, col.y, col.z)
        let camCol = cameraTransform.columns.3
        let camPos = SIMD3<Float>(camCol.x, camCol.y, camCol.z)
        let distFromCamera = simd_length(pos - camPos)

        guard distFromCamera <= maxPlausibleDistance else {
            onTapFailed("That tap landed unexpectedly far away — probably a different tree or the ground behind it. Try tapping a clearer, closer edge of this tree's canopy.")
            return
        }

        if let a = pointA, let aDist = pointADistance {
            let delta = abs(distFromCamera - aDist)
            guard delta <= maxPairDistanceDelta else {
                onTapFailed("That second tap landed much farther or closer than the first one — it likely hit a different object. Try tapping the matching edge of the same canopy.")
                return
            }

            let diff = pos - a
            let distMetres = Double(simd_length(diff))
            // LiDAR mesh typically doesn't reach the outermost canopy edge,
            // so taps land slightly inside the true drip line. Empirically
            // calibrated at 1.45 (45%) based on two trees — adjust if field
            // testing shows over/under.
            let distFeet = distMetres * 3.28084 * 1.45

            placeMarker(at: pos, color: .systemOrange, spread: activeSpread, isA: false)
            replaceLine(from: a, to: pos, spread: activeSpread)

            if activeSpread == 1 {
                spread1A = a; spread1B = pos
                spread1Binding.wrappedValue = distFeet
            } else {
                spread2A = a; spread2B = pos
                spread2Binding.wrappedValue = distFeet
            }

            pointA = nil
            pointADistance = nil

            if activeSpread == 1 && spread2Binding.wrappedValue == nil {
                activeSpread = 2
            } else if activeSpread == 2 && spread1Binding.wrappedValue == nil {
                activeSpread = 1
            } else {
                activeSpread = 0
            }
        } else {
            pointA = pos
            pointADistance = distFromCamera
            if activeSpread == 1 { spread1A = pos } else { spread2A = pos }
            placeMarker(at: pos, color: .systemBlue, spread: activeSpread, isA: true)
        }
    }

    // MARK: - Drag to reposition

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let sceneView else { return }

        switch gesture.state {
        case .began:
            let location = gesture.location(in: sceneView)
            let hits = sceneView.hitTest(location, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            guard let hit = hits.first(where: { isMarkerNode($0.node) }) else { return }
            let node = hit.node
            draggingNode = node
            draggingIsA = node.name?.hasSuffix("A") ?? false
            draggingSpread = node.name?.hasPrefix("s1") == true ? 1 : 2

        case .changed:
            guard let node = draggingNode else { return }
            let location = gesture.location(in: sceneView)

            var hitResult: ARRaycastResult? = nil
            if let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any) {
                hitResult = sceneView.session.raycast(query).first
            }
            if hitResult == nil, let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
                hitResult = sceneView.session.raycast(query).first
            }
            // Silently ignore frames where the raycast hits a wall or misses.
            guard let result = hitResult, result.targetAlignment != .vertical else { return }

            let col = result.worldTransform.columns.3
            let newPos = SIMD3<Float>(col.x, col.y, col.z)
            node.position = SCNVector3(newPos.x, newPos.y, newPos.z)

            if draggingSpread == 1 {
                if draggingIsA { spread1A = newPos } else { spread1B = newPos }
                if let a = spread1A, let b = spread1B {
                    replaceLine(from: a, to: b, spread: 1)
                    spread1Binding.wrappedValue = Double(simd_length(b - a)) * 3.28084 * 1.45
                }
            } else {
                if draggingIsA { spread2A = newPos } else { spread2B = newPos }
                if let a = spread2A, let b = spread2B {
                    replaceLine(from: a, to: b, spread: 2)
                    spread2Binding.wrappedValue = Double(simd_length(b - a)) * 3.28084 * 1.45
                }
            }

        case .ended, .cancelled:
            draggingNode = nil
            draggingSpread = 0

        default:
            break
        }
    }

    private func isMarkerNode(_ node: SCNNode) -> Bool {
        guard let name = node.name else { return false }
        return name == "s1A" || name == "s1B" || name == "s2A" || name == "s2B"
    }

    // MARK: - AR Markers & Lines

    private func placeMarker(at pos: SIMD3<Float>, color: UIColor, spread: Int, isA: Bool) {
        guard let sceneView else { return }
        let sphere = SCNSphere(radius: 0.04)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.9)
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        node.name = "s\(spread)\(isA ? "A" : "B")"
        sceneView.scene.rootNode.addChildNode(node)

        if spread == 1 {
            if isA { spread1MarkerA?.removeFromParentNode(); spread1MarkerA = node }
            else   { spread1MarkerB?.removeFromParentNode(); spread1MarkerB = node }
        } else {
            if isA { spread2MarkerA?.removeFromParentNode(); spread2MarkerA = node }
            else   { spread2MarkerB?.removeFromParentNode(); spread2MarkerB = node }
        }
    }

    private func replaceLine(from a: SIMD3<Float>, to b: SIMD3<Float>, spread: Int) {
        guard let sceneView else { return }

        if spread == 1 { spread1LineNode?.removeFromParentNode() }
        else            { spread2LineNode?.removeFromParentNode() }

        let diff = b - a
        let length = Double(simd_length(diff))
        guard length > 0 else { return }

        let box = SCNBox(width: CGFloat(length), height: 0.01, length: 0.01, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.8)
        box.materials = [mat]

        let node = SCNNode(geometry: box)
        node.name = "s\(spread)L"

        let mid = (a + b) * 0.5
        node.position = SCNVector3(mid.x, mid.y, mid.z)

        let dir = simd_normalize(diff)
        let xAxis = SIMD3<Float>(1, 0, 0)
        let cross = simd_cross(xAxis, dir)
        let dot   = simd_dot(xAxis, dir)
        if simd_length(cross) < 1e-6 {
            if dot < 0 { node.eulerAngles = SCNVector3(0, Float.pi, 0) }
        } else {
            let angle = acos(min(max(dot, -1), 1))
            let axis  = simd_normalize(cross)
            node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        }

        sceneView.scene.rootNode.addChildNode(node)
        if spread == 1 { spread1LineNode = node } else { spread2LineNode = node }
    }

    private func clearNodes(for spread: Int) {
        if spread == 1 {
            spread1MarkerA?.removeFromParentNode(); spread1MarkerA = nil
            spread1MarkerB?.removeFromParentNode(); spread1MarkerB = nil
            spread1LineNode?.removeFromParentNode(); spread1LineNode = nil
        } else {
            spread2MarkerA?.removeFromParentNode(); spread2MarkerA = nil
            spread2MarkerB?.removeFromParentNode(); spread2MarkerB = nil
            spread2LineNode?.removeFromParentNode(); spread2LineNode = nil
        }
    }
}
