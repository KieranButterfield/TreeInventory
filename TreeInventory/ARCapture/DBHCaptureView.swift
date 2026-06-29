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
    @State private var pendingLowConfidence: Bool = false
    @State private var showConfirm = false
    @State private var tapHint: String? = nil
    @State private var hintDismissTask: Task<Void, Never>? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // AR camera feed
            ARViewContainer(
                onResult: { circumferenceInches, sliceRef, lowConfidence in
                    tapHint = nil
                    pendingCircumferenceInches = circumferenceInches
                    pendingSliceRef = sliceRef
                    pendingLowConfidence = lowConfidence
                    showConfirm = true
                },
                onTapFailed: { reason in
                    showTapHint(reason)
                },
                onCircumferenceUpdate: { newCircumference in
                    pendingCircumferenceInches = newCircumference
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Instruction banner
                instructionBanner

                if let tapHint {
                    tapHintBanner(tapHint)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Result + confirm panel (slides up when a result arrives)
                if showConfirm, let circ = pendingCircumferenceInches {
                    resultPanel(circumferenceInches: circ)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showConfirm)
            .animation(.easeInOut(duration: 0.2), value: tapHint)
        }
    }

    // MARK: - Tap feedback

    /// Shows a brief on-screen reason when a tap doesn't produce a measurement,
    /// so the surveyor isn't tapping blindly with no feedback in the field.
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

    // MARK: - Sub-views

    private var instructionBanner: some View {
        Text(showConfirm
             ? "Pinch the ring to adjust the fit, then confirm"
             : "Slowly pan across the trunk at breast height for a couple seconds, then tap it")
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
    private func resultPanel(circumferenceInches: Double) -> some View {
        let dbhInches = circumferenceInches / .pi   // DBH = circumference / π

        VStack(spacing: 12) {
            Divider()

            if pendingLowConfidence {
                Label("Limited trunk view — this reading may run small. Retake and pan farther around the trunk first.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
            }

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
