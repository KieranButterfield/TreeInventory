//
//  DistanceCaptureView.swift
//  TreeInventory
//
//  AR-assisted horizontal distance measurement for the height tool.
//  Per the plan (Section 5.1): "Horizontal distance comes from a user-entered
//  value ... or an AR point-to-point tap when the base is within LiDAR range."
//
//  The surveyor taps the base of the trunk once; the app raycasts to find that
//  point in 3D space, then computes the horizontal (ground-plane) distance
//  from the device's current position to that point. Vertical difference is
//  intentionally ignored — this is the same "horizontal distance" the tangent
//  formula expects, not slant distance.
//

import SwiftUI
import ARKit
import SceneKit

/// Presents a live AR view; the surveyor taps the base of the trunk once,
/// and the resulting horizontal distance (in feet) is passed back.
struct DistanceCaptureView: View {

    var onComplete: (Double) -> Void

    @State private var pendingDistanceFeet: Double? = nil
    @State private var showConfirm = false
    @State private var tapHint: String? = nil
    @State private var hintDismissTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            DistanceARContainer(
                onResult: { distanceFeet in
                    tapHint = nil
                    pendingDistanceFeet = distanceFeet
                    showConfirm = true
                },
                onTapFailed: { reason in
                    showTapHint(reason)
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                instructionBanner

                if let tapHint {
                    tapHintBanner(tapHint)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showConfirm, let distance = pendingDistanceFeet {
                    resultPanel(distanceFeet: distance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showConfirm)
            .animation(.easeInOut(duration: 0.2), value: tapHint)
        }
        .navigationTitle("Distance to Tree")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tap feedback

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
            .padding(.top, 8)
    }

    private var instructionBanner: some View {
        Text("Tap the base of the trunk")
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultPanel(distanceFeet: Double) -> some View {
        VStack(spacing: 12) {
            Divider()

            VStack(spacing: 4) {
                Label("Horizontal Distance", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f ft", distanceFeet))
                    .font(.title2.monospacedDigit().bold())
            }

            HStack(spacing: 12) {
                Button("Retake") {
                    showConfirm = false
                    pendingDistanceFeet = nil
                }
                .buttonStyle(.bordered)

                Button("Use This Distance") {
                    onComplete(distanceFeet)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal)
        .background(.regularMaterial)
    }
}

// MARK: - AR container

private struct DistanceARContainer: UIViewRepresentable {

    var onResult: (Double) -> Void
    var onTapFailed: (String) -> Void = { _ in }

    func makeCoordinator() -> DistanceCoordinator {
        DistanceCoordinator(onResult: onResult, onTapFailed: onTapFailed)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.autoenablesDefaultLighting = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(DistanceCoordinator.handleTap(_:))
        )
        sceneView.addGestureRecognizer(tap)

        context.coordinator.sceneView = sceneView
        context.coordinator.startSession()

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: DistanceCoordinator) {
        coordinator.stopSession()
    }
}

// MARK: - Coordinator

@MainActor
private final class DistanceCoordinator: NSObject {

    weak var sceneView: ARSCNView?
    private let onResult: (Double) -> Void
    private let onTapFailed: (String) -> Void
    private var markerNode: SCNNode?

    init(onResult: @escaping (Double) -> Void, onTapFailed: @escaping (String) -> Void = { _ in }) {
        self.onResult = onResult
        self.onTapFailed = onTapFailed
    }

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.planeDetection = [.horizontal, .vertical]
        sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        sceneView?.session.pause()
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let sceneView else { return }
        let location = gesture.location(in: sceneView)

        // Existing plane geometry first, then a genuine fallback to
        // estimated-plane (depth-based) raycasting — same pattern as the
        // DBH tool, since the trunk base may not register as a flat plane.
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
            print("[DistanceCapture] Raycast or camera transform unavailable.")
            onTapFailed("No surface detected there. Move slightly closer, make sure the area is well lit, and pan the iPad across it for a second before tapping.")
            return
        }

        let tapPos = result.worldTransform.columns.3
        let camPos = cameraTransform.columns.3

        // Horizontal-only distance (ignore vertical/y difference) — this is
        // the "horizontal distance" the tangent-angle height formula expects.
        let dx = tapPos.x - camPos.x
        let dz = tapPos.z - camPos.z
        let distanceMeters = sqrt(dx * dx + dz * dz)
        let distanceFeet = Double(distanceMeters) * 3.28084

        placeMarker(at: SIMD3(tapPos.x, tapPos.y, tapPos.z))
        onResult(distanceFeet)
    }

    private func placeMarker(at pos: SIMD3<Float>) {
        guard let sceneView else { return }
        markerNode?.removeFromParentNode()

        let sphere = SCNSphere(radius: 0.03)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.9)
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        sceneView.scene.rootNode.addChildNode(node)
        markerNode = node
    }
}
