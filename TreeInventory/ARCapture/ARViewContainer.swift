//
//  ARViewContainer.swift
//  TreeInventory
//
//  UIViewRepresentable wrapping ARSCNView for LiDAR-based trunk DBH capture.
//
//  SETUP REQUIRED IN XCODE:
//  -------------------------
//  The app requires two Info.plist usage description keys. Because the project
//  uses GENERATE_INFOPLIST_FILE = YES, add these keys to the app target's
//  build settings (Xcode > target > Build Settings > search "Info.plist Values"):
//
//    INFOPLIST_KEY_NSCameraUsageDescription =
//        "Required for LiDAR tree measurement"
//
//    INFOPLIST_KEY_NSMotionUsageDescription =
//        "Required for height measurement"
//
//  You can also add them directly in Xcode via:
//    Target → Info → Custom iOS Target Properties → (+) add the keys:
//      NSCameraUsageDescription  → "Required for LiDAR tree measurement"
//      NSMotionUsageDescription  → "Required for height measurement"
//

import SwiftUI
import ARKit
import SceneKit
import Foundation

// MARK: - SwiftUI wrapper

/// Drop-in SwiftUI view that presents a live ARKit scene with LiDAR mesh capture.
/// The user taps on the trunk at breast height; the coordinator slices the mesh
/// and fits a circle to estimate circumference.
struct ARViewContainer: UIViewRepresentable {

    /// Called on the main actor when a valid circle fit is found.
    /// - Parameters:
    ///   - circumferenceInches: Trunk circumference in inches.
    ///   - pointCloudSliceRef: Path to a temp JSON file containing the [x, z] vertex slice.
    var onResult: (Double, String?) -> Void

    func makeCoordinator() -> ARSCNCoordinator {
        ARSCNCoordinator(onResult: onResult)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true

        // Tap gesture
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ARSCNCoordinator.handleTap(_:))
        )
        sceneView.addGestureRecognizer(tap)

        context.coordinator.sceneView = sceneView
        context.coordinator.startSession()

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARSCNCoordinator) {
        coordinator.stopSession()
    }
}

// MARK: - Coordinator

@MainActor
final class ARSCNCoordinator: NSObject, ARSCNViewDelegate {

    // MARK: State

    weak var sceneView: ARSCNView?
    private let onResult: (Double, String?) -> Void

    /// Overlay nodes so we can remove them on the next tap.
    private var overlayNodes: [SCNNode] = []

    // MARK: Init

    init(onResult: @escaping (Double, String?) -> Void) {
        self.onResult = onResult
    }

    // MARK: - Session lifecycle

    func startSession() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            print("[ARCapture] Device does not support LiDAR scene reconstruction.")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .automatic
        sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        sceneView?.session.pause()
    }

    // MARK: - Tap handling

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let sceneView = sceneView else { return }
        let location = gesture.location(in: sceneView)

        // Raycast against existing mesh geometry.
        guard
            let query = sceneView.raycastQuery(
                from: location,
                allowing: .existingPlaneGeometry,
                alignment: .any
            ) ?? sceneView.raycastQuery(
                from: location,
                allowing: .estimatedPlane,
                alignment: .any
            ),
            let result = sceneView.session.raycast(query).first
        else {
            print("[ARCapture] Raycast returned no result.")
            return
        }

        let hitWorldPos = result.worldTransform.columns.3  // SIMD4
        let hitY = hitWorldPos.y

        // Slice parameters
        let yTolerance: Float  = 0.01   // ±1 cm vertical band
        let hRadiusLimit: Float = 0.40  // 40 cm horizontal radius

        // Collect mesh vertices within the slice.
        var slicePoints: [(x: Float, z: Float)] = []

        guard let frame = sceneView.session.currentFrame else { return }

        for anchor in frame.anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            let geometry = meshAnchor.geometry
            let transform = meshAnchor.transform

            let vertices = geometry.vertices
            let vertexBuffer = vertices.buffer
            let vertexStride = vertices.stride
            let vertexOffset = vertices.offset

            let vertexCount = vertices.count
            let rawPtr = vertexBuffer.contents()

            for i in 0 ..< vertexCount {
                let ptr = rawPtr
                    .advanced(by: vertexOffset + i * vertexStride)
                    .assumingMemoryBound(to: SIMD3<Float>.self)
                let localPos = ptr.pointee

                // Transform vertex into world space.
                let worldPos4 = transform * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1)
                let wx = worldPos4.x
                let wy = worldPos4.y
                let wz = worldPos4.z

                // Vertical slice filter.
                guard abs(wy - hitY) <= yTolerance else { continue }

                // Horizontal radius filter.
                let dx = wx - hitWorldPos.x
                let dz = wz - hitWorldPos.z
                guard sqrt(dx * dx + dz * dz) <= hRadiusLimit else { continue }

                slicePoints.append((x: wx, z: wz))
            }
        }

        print("[ARCapture] Collected \(slicePoints.count) slice vertices.")

        guard let fit = KasaFit.fit(points: slicePoints) else {
            print("[ARCapture] Kasa fit failed — not enough points or degenerate system.")
            return
        }

        let circumferenceInches = KasaFit.circumferenceInches(fit.radius)
        let sliceRef = writeSliceJSON(slicePoints)

        // Draw AR overlay and deliver result on main actor (already here).
        removeOverlays()
        addCircleOverlay(center: SIMD3(fit.cx, hitY, fit.cz), radius: fit.radius)
        addLabelOverlay(
            text: String(format: "%.1f\" circ.", circumferenceInches),
            position: SIMD3(fit.cx, hitY + 0.15, fit.cz)
        )

        onResult(circumferenceInches, sliceRef)
    }

    // MARK: - AR overlays

    private func removeOverlays() {
        overlayNodes.forEach { $0.removeFromParentNode() }
        overlayNodes.removeAll()
    }

    private func addCircleOverlay(center: SIMD3<Float>, radius: Float) {
        guard let sceneView = sceneView else { return }

        // SCNTorus: ring radius = fit radius, pipe radius = thin visual tube.
        let torus = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: CGFloat(max(radius * 0.03, 0.005)))
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.85)
        material.isDoubleSided = true
        torus.materials = [material]

        let node = SCNNode(geometry: torus)
        node.position = SCNVector3(center.x, center.y, center.z)
        // SCNTorus lies in the XZ plane by default — no rotation needed.

        sceneView.scene.rootNode.addChildNode(node)
        overlayNodes.append(node)
    }

    private func addLabelOverlay(text: String, position: SIMD3<Float>) {
        guard let sceneView = sceneView else { return }

        let textGeom = SCNText(string: text, extrusionDepth: 0.001)
        textGeom.font = UIFont.boldSystemFont(ofSize: 0.05)
        textGeom.flatness = 0.005
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white
        textGeom.materials = [mat]

        let textNode = SCNNode(geometry: textGeom)

        // Center the text pivot.
        let (min, max) = textNode.boundingBox
        let cx = (max.x - min.x) / 2
        let cz = (max.z - min.z) / 2
        textNode.pivot = SCNMatrix4MakeTranslation(cx, 0, cz)

        // Billboard so it always faces the camera.
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .all
        textNode.constraints = [constraint]

        textNode.position = SCNVector3(position.x, position.y, position.z)
        textNode.scale = SCNVector3(1, 1, 1)

        sceneView.scene.rootNode.addChildNode(textNode)
        overlayNodes.append(textNode)
    }

    // MARK: - Slice JSON persistence

    /// Writes the slice point array to a temp file and returns the path.
    private func writeSliceJSON(_ points: [(x: Float, z: Float)]) -> String? {
        let payload = points.map { [Double($0.x), Double($0.z)] }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }

        let url = dir.appendingPathComponent("lidar_slice_\(Date().timeIntervalSince1970).json")
        try? data.write(to: url)
        return url.path
    }

    // MARK: - ARSCNViewDelegate

    nonisolated func renderer(_ renderer: any SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        nil   // We don't visualise the raw mesh; we only tap into it for data.
    }
}
