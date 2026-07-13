import SwiftUI

/// A single explanatory slide.
private struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let message: String
}

/// First-launch walkthrough. A paged slider that introduces what NTUSync does,
/// ending in a "Get Started" call to action. Completion is recorded by the
/// caller so it never shows again.
struct OnboardingView: View {
    /// Invoked when the user finishes or skips the walkthrough.
    var onFinished: () -> Void

    @State private var selection = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
            title: "Welcome to NTUSync",
            message: "Your offline companion for getting around NTU — routes, class times, and study spots, all on-device with no sign-in."
        ),
        OnboardingPage(
            symbol: "bus.fill",
            title: "Plan the fastest route",
            message: "Combine walking and campus shuttles to reach any building. NTUSync weighs live shuttle times so you always take the quickest way."
        ),
        OnboardingPage(
            symbol: "calendar",
            title: "Never miss your next class",
            message: "See when and where your next session is, with odd/even teaching weeks and recess handled automatically."
        ),
        OnboardingPage(
            symbol: "chair.lounge.fill",
            title: "Find a place to rest",
            message: "Discover nearby benches — filter for shelter from the sun and rain, and power outlets to charge up between classes."
        ),
        OnboardingPage(
            symbol: "location.fill.viewfinder",
            title: "Live directions on your lock screen",
            message: "Start a trip and a Live Activity keeps you on track — even offline — updating your progress as you move across campus."
        )
    ]

    private var isLastPage: Bool { selection == pages.count - 1 }

    var body: some View {
        ZStack {
            Brand.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    Button("Skip") { onFinished() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(isLastPage ? 0 : 1)
                        .disabled(isLastPage)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: selection)

                pageIndicator

                Button(action: advance) {
                    Text(isLastPage ? "Get Started" : "Next")
                        .font(.headline)
                        .foregroundStyle(Brand.navyDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 168, height: 168)
                Image(systemName: page.symbol)
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selection ? Brand.red : .white.opacity(0.25))
                    .frame(width: index == selection ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
            }
        }
        .padding(.bottom, 28)
    }

    private func advance() {
        if isLastPage {
            onFinished()
        } else {
            withAnimation { selection += 1 }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
