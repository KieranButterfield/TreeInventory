//
//  OnboardingView.swift
//  TreeInventory
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(OnboardingPage.all.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                Button("Skip") {
                    isPresented = false
                }
                .foregroundStyle(.secondary)

                Spacer()

                if currentPage < OnboardingPage.all.count - 1 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Page view

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: page.systemImage)
                .font(.system(size: 68))
                .foregroundStyle(.tint)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Page content

struct OnboardingPage {
    let systemImage: String
    let title: String
    let body: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "leaf.fill",
            title: "Welcome to Tree Inventory",
            body: "A field tool for LiDAR tree measurement and multi-surveyor data sync."
        ),
        OnboardingPage(
            systemImage: "folder.fill",
            title: "Start with a Project",
            body: "Create a project on the Home tab and add site codes. Every tree you measure lives inside a project.\n\nTap a project row to see its trees, or tap Measure to record a new one."
        ),
        OnboardingPage(
            systemImage: "camera.viewfinder",
            title: "DBH Measurement",
            body: "Slowly pan the camera across the trunk at breast height (4.5 ft up) for a few seconds, then tap the trunk.\n\nA ring appears from the LiDAR fit — pinch to resize it until it matches the trunk, then confirm."
        ),
        OnboardingPage(
            systemImage: "arrow.up.to.line",
            title: "Tree Height",
            body: "Enter your horizontal distance first — use a tape measure, not pacing, for accurate results.\n\nSight the base, then the top. If the angle warning appears, back up further before locking."
        ),
        OnboardingPage(
            systemImage: "arrow.left.and.right",
            title: "Crown Spread",
            body: "Walk to the canopy edge (drip line) and measure straight across with a tape.\n\nTake two readings at roughly 90° to each other and type them directly into the fields on Step 3."
        ),
        OnboardingPage(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Team Sync & Export",
            body: "Add your Supabase URL and anon key in Export & Settings to sync with your team.\n\nYou can also export a CSV at any time in EpicCollect5 format."
        ),
        OnboardingPage(
            systemImage: "checkmark.circle.fill",
            title: "You're Ready",
            body: "Tap the ? button at any time to revisit this guide.\n\nGood luck in the field."
        ),
    ]
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
