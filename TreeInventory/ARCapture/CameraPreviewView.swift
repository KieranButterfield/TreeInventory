//
//  CameraPreviewView.swift
//  TreeInventory
//
//  Live back-camera passthrough used as an aiming aid while sighting the
//  tree base/top angles in HeightCaptureView. Paired with AimBarOverlay,
//  which draws a horizontal colored bar across the feed at the point the
//  camera is aimed — as the surveyor tilts the iPad, the tree's image pans
//  up/down behind that fixed bar, making it easy to see exactly where the
//  camera is pointed relative to the trunk base or treetop.
//
//  Handles device rotation explicitly: AVCaptureVideoPreviewLayer does not
//  rotate itself automatically, so without this the feed would appear
//  sideways or upside-down depending on how the iPad is held (portrait,
//  landscape either way, or upside-down "from either end"). This observes
//  UIDevice orientation notifications and keeps the preview layer's
//  videoRotationAngle in sync.
//

import SwiftUI
import AVFoundation
import UIKit

final class CameraPreviewController: UIViewController {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.treeinventory.cameraPreview")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        configureSession()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateRotation(for: UIDevice.current.orientation)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    @objc private func orientationChanged() {
        updateRotation(for: UIDevice.current.orientation)
    }

    /// Keeps the preview's rotation matched to how the iPad is actually
    /// being held. Orientations that don't tell us which way is "up" on
    /// screen (face up/down flat on a table, or unknown) are ignored — the
    /// preview just keeps whatever rotation it last had.
    private func updateRotation(for orientation: UIDeviceOrientation) {
        guard orientation.isValidInterfaceOrientation else { return }
        let angle: CGFloat
        // Measured against this iPad's back camera: the commonly-cited
        // angle table (portrait=90, etc.) rendered the feed upside down in
        // the field, so these are rotated 180° from that to match what's
        // actually correct on this hardware.
        switch orientation {
        case .portrait:           angle = 270
        case .portraitUpsideDown: angle = 90
        case .landscapeLeft:      angle = 0
        case .landscapeRight:     angle = 180
        default: return
        }
        if let connection = previewLayer?.connection,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.updateRotation(for: UIDevice.current.orientation)
            }
        }
    }

    func stop() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self)
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

/// SwiftUI wrapper around the live camera passthrough.
struct CameraPreviewView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraPreviewController {
        CameraPreviewController()
    }

    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: CameraPreviewController, coordinator: ()) {
        uiViewController.stop()
    }
}

/// Horizontal aim line and caption drawn over the live camera feed.
/// The line is at the exact vertical centre of the frame — the point the
/// camera is aimed at. A centre dot aids precise target alignment.
struct AimBarOverlay: View {
    let caption: String
    let tooSteep: Bool

    private var tint: Color { tooSteep ? .orange : .yellow }

    var body: some View {
        ZStack {
            // ── Aim line ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    // Dark backing strip for contrast against bright sky.
                    Rectangle()
                        .fill(.black.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)

                    // Coloured aim line.
                    Rectangle()
                        .fill(tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)

                    // Centre dot for precise target alignment.
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.8), radius: 1)
                }

                Spacer(minLength: 0)
            }

            // ── Caption ────────────────────────────────────────────────────
            VStack {
                Spacer()
                Text(caption)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 10)
            }
        }
        .allowsHitTesting(false)
    }
}
