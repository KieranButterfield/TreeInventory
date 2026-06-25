//
//  HeightCaptureView.swift
//  TreeInventory
//
//  CoreMotion tangent-angle hypsometer.
//
//  Formula:
//    height = distance × (tan(topAngle) + tan(baseAngle))
//
//  where angles are device pitch (tilt from horizontal) in radians,
//  with positive pitch meaning the device is tilted upward.
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
            // Pitch: positive = nose up, negative = nose down.
            self.livePitch = motion.attitude.pitch
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

    /// Which sighting phase is active: nil = none, true = base, false = top
    @State private var sightingBase: Bool? = nil

    // MARK: - Derived

    private var distanceFeet: Double? {
        Double(distanceText)
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section("Horizontal Distance") {
                HStack {
                    TextField("Distance (feet)", text: $distanceText)
                        .keyboardType(.decimalPad)
                    Text("ft")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sight Base of Trunk") {
                sightRow(
                    label: "Base angle",
                    lockedAngle: motion.baseAngle,
                    isActive: sightingBase == true
                ) {
                    startSighting(base: true)
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
                        Text(String(format: "%.1f ft", computedHeight))
                            .font(.title2.monospacedDigit().bold())

                        Text("Override if needed:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Height (feet)", text: $overrideText)
                                .keyboardType(.decimalPad)
                            Text("ft")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Use This Height") {
                        let finalHeight = Double(overrideText) ?? computedHeight
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
                // Live pitch display
                HStack {
                    Image(systemName: "scope")
                    Text(String(format: "Live: %.2f°", motion.livePitch * 180 / .pi))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.blue)
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
        // Both angles are device pitch (radians).
        // Base angle is typically negative (looking down); top angle is positive (looking up).
        // Formula works for both signs as long as we add the tangents.
        let h = dist * (tan(topA) + tan(baseA))
        computedHeight = max(h, 0)  // clamp to ≥ 0 (guard against bad input)
        overrideText = String(format: "%.1f", max(h, 0))
    }
}
