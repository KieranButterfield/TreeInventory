//
//  DistanceCaptureView.swift
//  TreeInventory
//
//  AR-assisted horizontal distance measurement for the height tool.
//  Two modes:
//    LiDAR tap  — tap the trunk base (works within ~10 ft / LiDAR range)
//    Walk       — mark tree base, walk to spot, mark position; ARKit computes
//                 the horizontal distance between the two recorded world positions.
//                 Works at any distance the device can track.
//

import SwiftUI
import ARKit
import SceneKit

// MARK: - Main view

struct DistanceCaptureView: View {

    var onComplete: (Double) -> Void

    // MARK: - Mode

    private enum MeasureMode { case lidar, walk }
    private enum WalkPhase  { case markTree, markUser, confirm }

    @State private var mode: MeasureMode = .lidar
    @State private var coordinator: DistanceCoordinator? = nil

    // LiDAR state
    @State private var pendingDistanceFeet: Double? = nil
    @State private var showConfirm = false
    @State private var tapHint: String? = nil
    @State private var hintDismissTask: Task<Void, Never>? = nil

    // Walk state
    @State private var walkPhase: WalkPhase = .markTree
    @State private var treeWorldPos: SIMD3<Float>? = nil
    @State private var walkDistanceFeet: Double? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            DistanceARContainer(
                tapEnabled: mode == .lidar,
                onResult: { distanceFeet in
                    tapHint = nil
                    pendingDistanceFeet = distanceFeet
                    showConfirm = true
                },
                onTapFailed: { reason in
                    showTapHint(reason)
                },
                onCoordinatorReady: { coord in
                    coordinator = coord
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("LiDAR tap").tag(MeasureMode.lidar)
                    Text("Walk to measure").tag(MeasureMode.walk)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                switch mode {
                case .lidar:  lidarUI
                case .walk:   walkUI
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showConfirm)
            .animation(.easeInOut(duration: 0.2), value: tapHint)
            .animation(.easeInOut(duration: 0.2), value: mode)
            .onChange(of: mode) { _, _ in resetAll() }
        }
        .navigationTitle("Distance to Tree")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - LiDAR UI

    @ViewBuilder private var lidarUI: some View {
        Text("Tap the ground directly at the base of the trunk")
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 8)
            .frame(maxWidth: .infinity)

        if let tapHint {
            tapHintBanner(tapHint)
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        if showConfirm, let distance = pendingDistanceFeet {
            resultPanel(distanceFeet: distance) {
                showConfirm = false
                pendingDistanceFeet = nil
                coordinator?.clearMarker()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Walk UI

    @ViewBuilder private var walkUI: some View {
        switch walkPhase {
        case .markTree:
            walkBanner(
                "Stand at the trunk base",
                detail: "Hold the device as close to the trunk as you can reach, then tap."
            )
            Button("Mark Tree Base") {
                if let pos = coordinator?.currentCameraPosition() {
                    treeWorldPos = pos
                    coordinator?.placeWalkMarker(at: pos, color: .systemGreen)
                    walkPhase = .markUser
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.vertical, 8)

        case .markUser:
            walkBanner(
                "Walk to your measuring spot",
                detail: "Walk steadily with the device at chest height. Tap when ready."
            )
            Button("Mark My Position") {
                guard let treePos = treeWorldPos,
                      let myPos = coordinator?.currentCameraPosition() else { return }
                let dx = myPos.x - treePos.x
                let dz = myPos.z - treePos.z
                walkDistanceFeet = Double(sqrt(dx * dx + dz * dz)) * 3.28084
                walkPhase = .confirm
            }
            .buttonStyle(.borderedProminent)
            .padding(.vertical, 8)

        case .confirm:
            if let distance = walkDistanceFeet {
                Text("Add trunk half-width (~0.5 ft for most trees) if you couldn't touch the trunk when marking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                resultPanel(distanceFeet: distance) {
                    walkPhase = .markTree
                    treeWorldPos = nil
                    walkDistanceFeet = nil
                    coordinator?.clearMarker()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func walkBanner(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared result panel

    @ViewBuilder
    private func resultPanel(distanceFeet: Double, onRetake: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Divider()

            VStack(spacing: 4) {
                Label("Horizontal Distance", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatFeetInches(distanceFeet))
                    .font(.title2.monospacedDigit().bold())
            }

            HStack(spacing: 12) {
                Button("Retake", action: onRetake)
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

    // MARK: - Helpers

    private func resetAll() {
        showConfirm = false
        pendingDistanceFeet = nil
        tapHint = nil
        walkPhase = .markTree
        treeWorldPos = nil
        walkDistanceFeet = nil
        coordinator?.clearMarker()
    }

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
}

// MARK: - AR container

private struct DistanceARContainer: UIViewRepresentable {

    var tapEnabled: Bool
    var onResult: (Double) -> Void
    var onTapFailed: (String) -> Void
    var onCoordinatorReady: (DistanceCoordinator) -> Void

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
        context.coordinator.tapEnabled = tapEnabled
        context.coordinator.startSession()
        onCoordinatorReady(context.coordinator)

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.tapEnabled = tapEnabled
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: DistanceCoordinator) {
        coordinator.stopSession()
    }
}

// MARK: - Coordinator

@MainActor
final class DistanceCoordinator: NSObject {

    weak var sceneView: ARSCNView?
    var tapEnabled = true
    private let onResult: (Double) -> Void
    private let onTapFailed: (String) -> Void
    private var markerNodes: [SCNNode] = []

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

    /// Returns the current device camera position in world space.
    func currentCameraPosition() -> SIMD3<Float>? {
        guard let col = sceneView?.session.currentFrame?.camera.transform.columns.3 else { return nil }
        return SIMD3(col.x, col.y, col.z)
    }

    /// Places a coloured sphere at a world position (used for tree-base marker in walk mode).
    func placeWalkMarker(at pos: SIMD3<Float>, color: UIColor) {
        guard let sceneView else { return }
        let sphere = SCNSphere(radius: 0.05)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.9)
        sphere.materials = [mat]
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        sceneView.scene.rootNode.addChildNode(node)
        markerNodes.append(node)
    }

    /// Removes all marker nodes from the scene.
    func clearMarker() {
        markerNodes.forEach { $0.removeFromParentNode() }
        markerNodes.removeAll()
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard tapEnabled, let sceneView else { return }
        let location = gesture.location(in: sceneView)

        var hitResult: ARRaycastResult? = nil
        if let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal) {
            hitResult = sceneView.session.raycast(query).first
        }
        if hitResult == nil, let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any) {
            hitResult = sceneView.session.raycast(query).first
        }
        if hitResult == nil, let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal) {
            hitResult = sceneView.session.raycast(query).first
        }
        if hitResult == nil, let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
            hitResult = sceneView.session.raycast(query).first
        }

        guard let result = hitResult,
              let cameraTransform = sceneView.session.currentFrame?.camera.transform
        else {
            onTapFailed("No surface detected there. Move slightly closer, make sure the area is well lit, and pan the iPad across it for a second before tapping.")
            return
        }

        let tapPos = result.worldTransform.columns.3
        let camPos = cameraTransform.columns.3
        let dx = tapPos.x - camPos.x
        let dz = tapPos.z - camPos.z
        let distanceFeet = Double(sqrt(dx * dx + dz * dz)) * 3.28084

        placeWalkMarker(at: SIMD3(tapPos.x, tapPos.y, tapPos.z), color: .systemBlue)
        onResult(distanceFeet)
    }
}
