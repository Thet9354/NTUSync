import SwiftUI

/// Top-level flow coordinator. Shows the branded splash on every cold launch,
/// then the onboarding walkthrough on first launch only, before handing off to
/// the main tabbed interface.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var phase: Phase = .splash

    private enum Phase {
        case splash
        case onboarding
        case main
    }

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = hasCompletedOnboarding ? .main : .onboarding
                    }
                }
                .transition(.opacity)

            case .onboarding:
                OnboardingView {
                    hasCompletedOnboarding = true
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .main
                    }
                }
                .transition(.opacity)

            case .main:
                ContentView()
                    .transition(.opacity)
            }
        }
    }
}
