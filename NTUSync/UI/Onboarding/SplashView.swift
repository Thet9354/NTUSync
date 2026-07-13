import SwiftUI

/// Branded launch screen shown while the app finishes seeding on cold start.
/// Animates the route mark drawing itself in, then reports completion.
struct SplashView: View {
    /// Invoked once the intro animation has played long enough to hand off.
    var onFinished: () -> Void

    @State private var drawProgress: CGFloat = 0
    @State private var titleShown = false

    var body: some View {
        ZStack {
            Brand.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                BrandMark(progress: drawProgress)
                    .frame(width: 160, height: 160)

                VStack(spacing: 6) {
                    Text("NTUSync")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Find your way around campus")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .opacity(titleShown ? 1 : 0)
                .offset(y: titleShown ? 0 : 8)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.1)) {
                drawProgress = 1
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.7)) {
                titleShown = true
            }
            try? await Task.sleep(for: .seconds(1.7))
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
