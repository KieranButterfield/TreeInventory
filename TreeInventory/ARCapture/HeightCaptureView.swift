//
//  HeightCaptureView.swift
//  TreeInventory
//
//  CoreMotion tangent-angle hypsometer.
//
//  Formula:
//    height = distance × (tan(topAngle) - tan(baseAngle))
//
//  where angles are the elevation angle of the device's BACK (the camera
//  side — the axis the surveyor actually aims at the tree while watching
//  the live readout on the screen) above horizontal, in radians,
//  positive = tilted up.
//
//  The angle is computed from the gravity vector rather than
//  CMAttitude.pitch, using gravity.z: in Apple's device-coordinate
//  convention the Z axis is the screen normal (points out of the screen,
//  toward the surveyor), so the back/camera axis is -Z, and its elevation
//  above horizontal is asin(gravity.z). This avoids Euler-angle
//  decomposition issues entirely, and — importantly — uses the axis that
//  matches how this tool is actually held (aiming the camera at the
//  tree), not the device's top edge. An earlier version of this code used
//  the top-edge (Y) axis, which stays close to vertical throughout normal
//  use here and barely changes between the base and top sightings —
//  that's what was producing near-identical (and so near-cancelling)
//  angles for every tree, regardless of true height.
//
//  NOTE: NSMotionUsageDescription must be present in the app's Info.plist.
//  See ARViewContainer.swift for the Xcode build-settings key to add.
//

import SwiftUI
import CoreMotion

@Observable
private final class HeightMotionState {
    var livePitch: Double = 0        // radians, updated while sighting
    var baseAngle: Double? = nil     // locked base angle (radians)
    var topAngle:  Double? = nil     // locked top angle (radians)
    var isSighting = false

    private let motionManager = CMMotionManager()

    func startSighting() {
        guard motionManager.isDeviceMotionAvailable else { return }
        isSighting = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Elevation angle of the device's back/camera axis above
            // horizontal, from the gravity vector (see header comment).
            let gz = min(max(motion.gravity.z, -1), 1)
            self.livePitch = asin(gz)
        }
    }

    func lockAngle() -> Double {
        stopSighting()
        return livePitch
    }

    func stopSighting() {
        isSighting = false
        motionManager.stopDeviceMotionUpdates()
    }
}

/// Tangent-angle height measurement using CoreMotion.
///
/// Flow:
/// 1. Enter horizontal distance (feet).
/// 2. Tap "Sight Base" → point phone at trunk base → tap "Lock".
/// 3. Tap "Sight Top" → point phone at treetop → tap "Lock".
/// 4. Review computed height, optionally edit, then tap "Use This Height".
struct HeightCaptureView: View {

    var onComplete: (CaptureResult) -> Void

    // MARK: - State

    @State private var motion = HeightMotionState()

    @State private var distanceText = ""
    @State private var computedHeight: Double? = nil
    @State private var overrideText = ""
    @State private var showingDistanceCapture = false

    /// Which sighting phase is active: nil = none, true = base, false = top
    @State private var sightingBase: Bool? = nil

    // MARK: - Derived

    private var distanceFeet: Double? {
        parseFeet(distanceText)
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("e.g. 9'8\", 9.7 ft, 116 in", text: $distanceText)
                        .keyboardType(.default)
                    Text("ft")
                        .foregroundStyle(.secondary)
                }

                Button {
                    showingDistanceCapture = true
                } label: {
                    Label("Measure with AR", systemImage: "camera.viewfinder")
                }
            } header: {
                Text("Horizontal Distance")
            } footer: {
                Text("AR works within ~10 ft; farther, use a tape measure.")
            }

            Section {
                sightRow(
                    label: "Base angle",
                    lockedAngle: motion.baseAngle,
                    isActive: sightingBase == true
                ) {
                    startSighting(base: true)
                }
            } header: {
                Text("Sight Base of Trunk")
            } footer: {
                if sightingBase != nil || motion.baseAngle == nil {
                    Text("Keep the iPad at the same spot and height for this and the top sighting.")
                }
            }

            Section("Sight Top of Crown") {
                sightRow(
                    label: "Top angle",
                    lockedAngle: motion.topAngle,
                    isActive: sightingBase == false
                ) {
                    startSighting(base: false)
                }
            }

            if let computedHeight {
                Section("Computed Height") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formatFeetInches(computedHeight))
                            .font(.title2.monospacedDigit().bold())

                        Text("Override if needed:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("e.g. 6'10\", 6.8 ft, 82 in", text: $overrideText)
                            .keyboardType(.default)
                    }

                    Button("Use This Height") {
                        let finalHeight = parseFeet(overrideText) ?? computedHeight
                        onComplete(CaptureResult(heightFeet: finalHeight))
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Height Capture")
        .onChange(of: motion.baseAngle) { _, _ in recalculate() }
        .onChange(of: motion.topAngle)  { _, _ in recalculate() }
        .onChange(of: distanceText)     { _, _ in recalculate() }
        .onDisappear { motion.stopSighting() }
        .sheet(isPresented: $showingDistanceCapture) {
            NavigationStack {
                DistanceCaptureView { distanceFeet in
                    distanceText = formatFeetInches(distanceFeet)
                    showingDistanceCapture = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingDistanceCapture = false }
                    }
                }
            }
        }
    }

    // MARK: - Sight row

    @ViewBuilder
    private func sightRow(
        label: String,
        lockedAngle: Double?,
        isActive: Bool,
        onSight: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isActive {
                let liveDegrees = motion.livePitch * 180 / .pi
                let tooSteep = abs(liveDegrees) > 70
                // tan() grows explosively as the angle approaches 90° — past
                // ~80° even a tiny aiming error turns into a large height
                // error, so this gets its own, more direct warning rather
                // than just the orange tint.
                let extremelySteep = abs(liveDegrees) > 80
                let caption = label == "Base angle"
                    ? "Line up the bar with where the trunk meets the ground"
                    : "Line up the bar with the top of the crown"

                // Live camera feed with a horizontal aim bar overlaid where
                // the lens is pointed. The preview layer is kept correctly
                // rotated for whichever way the iPad is held (portrait,
                // landscape either direction, or upside-down), so the bar
                // stays meaningful relative to the tree in frame no matter
                // how the surveyor is holding the device.
                ZStack {
                    CameraPreviewView()
                    AimBarOverlay(caption: caption, tooSteep: tooSteep)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.vertical, 4)

                if extremelySteep {
                    Text("Very steep angle — back up farther for an accurate reading.")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } else if tooSteep {
                    Text("Getting steep — more distance from the tree improves accuracy.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // Live pitch display
                HStack {
                    Image(systemName: "scope")
                    Text(String(format: "Live: %.2f°", liveDegrees))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(tooSteep ? .orange : .blue)
                    Spacer()
                    Button("Lock") {
                        let angle = motion.lockAngle()
                        if sightingBase == true {
                            motion.baseAngle = angle
                        } else {
                            motion.topAngle = angle
                        }
                        sightingBase = nil
                    }
                    .buttonStyle(.borderedProminent)
                }

            } else if let angle = lockedAngle {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(format: "%@ locked: %.2f°", label, angle * 180 / .pi))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-sight") { onSight() }
                        .font(.caption)
                }
            } else {
                Button(action: onSight) {
                    Label("Sight \(label == "Base angle" ? "Base" : "Top")", systemImage: "scope")
                }
            }
        }
    }

    // MARK: - Actions

    private func startSighting(base: Bool) {
        sightingBase = base
        motion.startSighting()
    }

    private func recalculate() {
        guard
            let dist = distanceFeet, dist > 0,
            let baseA = motion.baseAngle,
            let topA  = motion.topAngle
        else {
            computedHeight = nil
            return
        }
        // Both angles are signed device pitch (radians), positive = tilted up,
        // negative = tilted down. Height = D * (tan(topAngle) - tan(baseAngle)):
        // when the base is below eye level (the normal case), baseAngle is
        // negative, so subtracting it ADDS the eye-height contribution.
        // (The classic hypsometer formula "D*(tanα + tanβ)" uses two unsigned
        // angles measured in opposite directions — that's equivalent to this
        // once baseAngle's sign is accounted for. Using "+" directly on signed
        // pitch values was the bug: it canceled out most or all of the eye-height
        // term, which is why short trees with both angles negative came out
        // near zero.)
        let h = dist * (tan(topA) - tan(baseA))
        computedHeight = max(h, 0)  // clamp to ≥ 0 (guard against bad input)
        overrideText = formatFeetInches(max(h, 0))
    }
}
