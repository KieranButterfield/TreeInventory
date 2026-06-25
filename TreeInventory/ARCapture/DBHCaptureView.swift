//
//  DBHCaptureView.swift
//  TreeInventory
//
//  SwiftUI wrapper around ARViewContainer for DBH measurement.
//

import SwiftUI

/// Presents the LiDAR-based trunk DBH capture flow.
///
/// The user taps the trunk at breast height (~1.37 m / 4.5 ft above ground).
/// When ARViewContainer delivers a circumference result the surveyor reviews it
/// and taps "Use This Measurement" to confirm.
struct DBHCaptureView: View {

    /// Called when the surveyor confirms the measurement.
    var onComplete: (CaptureResult) -> Void

    // MARK: - State

    @State private var pendingCircumferenceInches: Double? = nil
    @State private var pendingSliceRef: String? = nil
    @State private var showConfirm = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // AR camera feed
            ARViewContainer { circumferenceInches, sliceRef in
                pendingCircumferenceInches = circumferenceInches
                pendingSliceRef = sliceRef
                showConfirm = true
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Instruction banner
                instructionBanner

                // Result + confirm panel (slides up when a result arrives)
                if showConfirm, let circ = pendingCircumferenceInches {
                    resultPanel(circumferenceInches: circ)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showConfirm)
        }
    }

    // MARK: - Sub-views

    private var instructionBanner: some View {
        Text("Tap the trunk at breast height")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultPanel(circumferenceInches: Double) -> some View {
        let dbhInches = circumferenceInches / .pi   // DBH = circumference / π

        VStack(spacing: 12) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Circumference", systemImage: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f in", circumferenceInches))
                        .font(.title2.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Label("DBH", systemImage: "ruler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f in", dbhInches))
                        .font(.title2.monospacedDigit())
                        .bold()
                }
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Retake") {
                    showConfirm = false
                    pendingCircumferenceInches = nil
                    pendingSliceRef = nil
                }
                .buttonStyle(.bordered)

                Button("Use This Measurement") {
                    onComplete(
                        CaptureResult(
                            dbhInches: dbhInches,
                            pointCloudSliceRef: pendingSliceRef
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }
}
