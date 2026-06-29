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
/// The coordinator auto-detects the trunk at 4'4" breast height once it finds a
/// stable circle fit. The user can also tap manually as a fallback.
struct ARViewContainer: UIViewRepresentable {

    var onResult: (Double, String?, Bool) -> Void
    var onTapFailed: (String) -> Void = { _ in }
    var onCircumferenceUpdate: (Double) -> Void = { _ in }
    /// Called once the coordinator is ready — lets the parent view hold a
    /// reference so it can call resetForRetake() when the surveyor taps Retake.
    var onCoordinatorReady: (ARSCNCoordinator) -> Void = { _ in }

    func makeCoordinator() -> ARSCNCoordinator {
        ARSCNCoordinator(
            onResult: onResult,
            onTapFailed: onTapFailed,
            onCircumferenceUpdate: onCircumferenceUpdate
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ARSCNCoordinator.handleTap(_:))
        )
        sceneView.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(ARSCNCoordinator.handlePinch(_:))
        )
        sceneView.addGestureRecognizer(pinch)

        context.coordinator.sceneView = sceneView
        context.coordinator.startSession()
        onCoordinatorReady(context.coordinator)

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
    private let onResult: (Double, String?, Bool) -> Void
    private let onTapFailed: (String) -> Void
    private let onCircumferenceUpdate: (Double) -> Void

    private var overlayNodes: [SCNNode] = []
    private var activeTorus: SCNTorus?
    private var activeLabelGeom: SCNText?
    private var pendingRadius: Float = 0

    // MARK: Auto-scan

    /// Measurement height in metres. Default is 4'4" (1.3208 m) for standard DBH.
    /// Set to 0.1524 m (6") for sub-breast-height trees via setMeasurementHeight(_:).
    private var measurementHeightMeters: Float = 1.3208

    private var autoTimer: Timer?
    private var recentFitRadii: [Float] = []
    /// Suppresses the auto-scan timer once a result is delivered. Reset by
    /// resetForRetake() when the surveyor taps the Retake button.
    private var isLocked = false
    private let stabilityCount = 4         // consecutive stable fits required
    private let stabilityCV: Float = 0.06  // max coefficient of variation

    // MARK: Init

    init(
        onResult: @escaping (Double, String?, Bool) -> Void,
        onTapFailed: @escaping (String) -> Void = { _ in },
        onCircumferenceUpdate: @escaping (Double) -> Void = { _ in }
    ) {
        self.onResult = onResult
        self.onTapFailed = onTapFailed
        self.onCircumferenceUpdate = onCircumferenceUpdate
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
        config.planeDetection = [.horizontal, .vertical]
        sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        startAutoScan()
    }

    func stopSession() {
        stopAutoScan()
        sceneView?.session.pause()
    }

    /// Switches between standard (4'4") and low (6") measurement height and restarts the scan.
    func setMeasurementHeight(_ meters: Float) {
        measurementHeightMeters = meters
        resetForRetake()
    }

    /// Clears the ring and restarts auto-scanning. Call when the surveyor taps Retake.
    func resetForRetake() {
        isLocked = false
        recentFitRadii.removeAll()
        removeOverlays()
        startAutoScan()
    }

    // MARK: - Auto-scan

    private func startAutoScan() {
        stopAutoScan()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tryAutoFit() }
        }
    }

    private func stopAutoScan() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    private func tryAutoFit() {
        guard !isLocked, let sceneView else { return }

        // Raycast from the screen centre to find the trunk's XZ position.
        let centre = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        var hit: ARRaycastResult?
        if let q = sceneView.raycastQuery(from: centre, allowing: .existingPlaneGeometry, alignment: .any) {
            hit = sceneView.session.raycast(q).first
        }
        if hit == nil,
           let q = sceneView.raycastQuery(from: centre, allowing: .estimatedPlane, alignment: .any) {
            hit = sceneView.session.raycast(q).first
        }
        guard let result = hit else { recentFitRadii.removeAll(); return }

        let col = result.worldTransform.columns.3
        // Use detected ground + 4'4" if available; fall back to hit Y (user must
        // hold device at breast height in that case).
        let sliceY = breastHeightWorldY() ?? col.y

        let points = collectSlicePoints(centerX: col.x, sliceY: sliceY, centerZ: col.z)
        guard points.count >= 8, let fit = KasaFit.fit(points: points) else {
            recentFitRadii.removeAll()
            return
        }

        recentFitRadii.append(fit.radius)
        if recentFitRadii.count > stabilityCount { recentFitRadii.removeFirst() }
        guard recentFitRadii.count >= stabilityCount else { return }

        let mean = recentFitRadii.reduce(0, +) / Float(recentFitRadii.count)
        let sd   = sqrt(recentFitRadii.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(recentFitRadii.count))
        guard sd / mean < stabilityCV else { return }

        // Stable — lock and deliver.
        deliverResult(hitX: col.x, hitZ: col.z, cx: fit.cx, cz: fit.cz, sliceY: sliceY, points: points, radius: mean)
    }

    // MARK: - Manual tap (fallback / override)

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isLocked, let sceneView else { return }
        let location = gesture.location(in: sceneView)

        var hit: ARRaycastResult?
        if let q = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any) {
            hit = sceneView.session.raycast(q).first
        }
        if hit == nil,
           let q = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
            hit = sceneView.session.raycast(q).first
        }

        guard let result = hit else {
            onTapFailed("No surface detected there. Move slightly closer, make sure the trunk is well lit, and pan the iPad across it for a second before tapping.")
            return
        }

        guard sceneView.session.currentFrame != nil else {
            onTapFailed("Tracking isn't ready yet. Wait a moment and try again.")
            return
        }

        let col = result.worldTransform.columns.3
        let sliceY = breastHeightWorldY() ?? col.y
        let points = collectSlicePoints(centerX: col.x, sliceY: sliceY, centerZ: col.z)

        print("[ARCapture] Manual tap — \(points.count) points at y=\(String(format: "%.2f", sliceY)) m\(breastHeightWorldY() != nil ? " (ground detected)" : " (camera height)")")

        guard let fit = KasaFit.fit(points: points) else {
            onTapFailed("Found the surface but couldn't get a clean measurement (\(points.count) points). Try tapping a flatter section of trunk, or back up slightly and pan around it first.")
            return
        }

        deliverResult(hitX: col.x, hitZ: col.z, cx: fit.cx, cz: fit.cz, sliceY: sliceY, points: points, radius: fit.radius)
    }

    private func deliverResult(hitX: Float, hitZ: Float, cx: Float, cz: Float, sliceY: Float, points: [(x: Float, z: Float)], radius: Float) {
        isLocked = true
        stopAutoScan()

        let circumferenceInches = KasaFit.circumferenceInches(radius)
        let sliceRef = writeSliceJSON(points)
        let coverage = angularCoverageDegrees(of: points, aroundCenter: (cx, cz))
        let lowConfidence = coverage < 110

        // Kasa fit is biased toward the camera when only a partial arc is visible.
        // Correct by anchoring the ring's near edge at the visible trunk surface:
        // ring_center = hit_point + radius * normalize(hit - camera)
        var ringCX = cx, ringCZ = cz
        if let frame = sceneView?.session.currentFrame {
            let camX = frame.camera.transform.columns.3.x
            let camZ = frame.camera.transform.columns.3.z
            let dx = hitX - camX, dz = hitZ - camZ
            let dist = sqrt(dx * dx + dz * dz)
            if dist > 0.01 {
                ringCX = hitX + (dx / dist) * radius
                ringCZ = hitZ + (dz / dist) * radius
            }
        }

        print("[ARCapture] Result: radius=\(String(format: "%.3f", radius))m circ=\(Int(circumferenceInches))\" arc=\(Int(coverage))°")

        removeOverlays()
        addCircleOverlay(center: SIMD3(ringCX, sliceY, ringCZ), radius: radius)
        addLabelOverlay(
            text: String(format: "%.1f\" circ.", circumferenceInches),
            position: SIMD3(ringCX, sliceY + 0.15, ringCZ)
        )
        onResult(circumferenceInches, sliceRef, lowConfidence)
    }

    // MARK: - Helpers

    /// World Y of 4'4" above the largest detected horizontal ground plane.
    /// Returns nil if no horizontal plane has been found yet (e.g. just started scanning).
    /// Ceiling planes are excluded by requiring the plane to be below the camera.
    private func breastHeightWorldY() -> Float? {
        guard let frame = sceneView?.session.currentFrame else { return nil }
        let cameraY = frame.camera.transform.columns.3.y
        let groundAnchors = frame.anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .filter { $0.alignment == .horizontal }
            .filter { $0.transform.columns.3.y < cameraY - 0.3 }  // exclude ceiling/waist-height planes
        guard !groundAnchors.isEmpty else { return nil }
        // Largest horizontal plane is the most reliably detected ground surface.
        let ground = groundAnchors.max(by: {
            ($0.planeExtent.width * $0.planeExtent.height) < ($1.planeExtent.width * $1.planeExtent.height)
        })!
        return ground.transform.columns.3.y + measurementHeightMeters
    }

    /// Collects LiDAR mesh vertices within ±2 cm of sliceY and within 40 cm
    /// horizontal radius of (centerX, centerZ).
    private func collectSlicePoints(centerX: Float, sliceY: Float, centerZ: Float) -> [(x: Float, z: Float)] {
        guard let frame = sceneView?.session.currentFrame else { return [] }
        let yTol: Float   = 0.02
        let hRadius: Float = 0.40
        var pts: [(x: Float, z: Float)] = []
        for anchor in frame.anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            let verts = mesh.geometry.vertices
            let raw   = verts.buffer.contents()
            for i in 0..<verts.count {
                let ptr = raw
                    .advanced(by: verts.offset + i * verts.stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self)
                let w = mesh.transform * SIMD4<Float>(ptr.pointee.x, ptr.pointee.y, ptr.pointee.z, 1)
                guard abs(w.y - sliceY) <= yTol else { continue }
                let dx = w.x - centerX, dz = w.z - centerZ
                guard dx*dx + dz*dz <= hRadius*hRadius else { continue }
                pts.append((x: w.x, z: w.z))
            }
        }
        return pts
    }

    private func angularCoverageDegrees(of points: [(x: Float, z: Float)], aroundCenter center: (Float, Float)) -> Float {
        guard points.count >= 2 else { return 0 }
        let angles = points.map { atan2($0.z - center.1, $0.x - center.0) }.sorted()
        var maxGap: Float = 0
        for i in 0..<angles.count {
            let next = i + 1 < angles.count ? angles[i + 1] : angles[0] + 2 * Float.pi
            maxGap = max(maxGap, next - angles[i])
        }
        return ((2 * Float.pi) - maxGap) * 180 / .pi
    }

    // MARK: - AR overlays

    private func removeOverlays() {
        overlayNodes.forEach { $0.removeFromParentNode() }
        overlayNodes.removeAll()
        activeTorus = nil
        activeLabelGeom = nil
        pendingRadius = 0
    }

    private func addCircleOverlay(center: SIMD3<Float>, radius: Float) {
        guard let sceneView else { return }
        pendingRadius = radius
        let torus = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: CGFloat(max(radius * 0.03, 0.005)))
        activeTorus = torus
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.85)
        mat.isDoubleSided = true
        torus.materials = [mat]
        let node = SCNNode(geometry: torus)
        node.position = SCNVector3(center.x, center.y, center.z)
        sceneView.scene.rootNode.addChildNode(node)
        overlayNodes.append(node)
    }

    private func addLabelOverlay(text: String, position: SIMD3<Float>) {
        guard let sceneView else { return }
        let textGeom = SCNText(string: text, extrusionDepth: 0.001)
        activeLabelGeom = textGeom
        textGeom.font = UIFont.boldSystemFont(ofSize: 0.05)
        textGeom.flatness = 0.005
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white
        textGeom.materials = [mat]
        let node = SCNNode(geometry: textGeom)
        let (mn, mx) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2, 0, (mx.z - mn.z) / 2)
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .all
        node.constraints = [constraint]
        node.position = SCNVector3(position.x, position.y, position.z)
        sceneView.scene.rootNode.addChildNode(node)
        overlayNodes.append(node)
    }

    // MARK: - Pinch to adjust ring

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed,
              let torus = activeTorus,
              pendingRadius > 0
        else { return }
        pendingRadius = max(pendingRadius * Float(gesture.scale), 0.01)
        gesture.scale = 1.0
        torus.ringRadius = CGFloat(pendingRadius)
        torus.pipeRadius = CGFloat(max(pendingRadius * 0.03, 0.005))
        let newCirc = KasaFit.circumferenceInches(pendingRadius)
        activeLabelGeom?.string = String(format: "%.1f\" circ.", newCirc)
        onCircumferenceUpdate(newCirc)
    }

    // MARK: - Slice JSON persistence

    private func writeSliceJSON(_ points: [(x: Float, z: Float)]) -> String? {
        let payload = points.map { [Double($0.x), Double($0.z)] }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let dir  = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let url = dir.appendingPathComponent("lidar_slice_\(Date().timeIntervalSince1970).json")
        try? data.write(to: url)
        return url.path
    }

    // MARK: - ARSCNViewDelegate

    nonisolated func renderer(_ renderer: any SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        nil
    }
}
