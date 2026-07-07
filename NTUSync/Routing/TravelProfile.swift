import Foundation

/// A customizable travel-cost matrix. Edge cost is
/// `time · (1 + rainAversion·exposure + slopeAversion·max(0, Δh/len))`,
/// plus `shuttleBoardingPenalty` once per boarding.
nonisolated struct TravelProfile: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let displayName: String
    var walkSpeedMetresPerSecond: Double
    var rainAversion: Double
    var slopeAversion: Double
    var allowsStairs: Bool
    /// Extra seconds charged when boarding a shuttle; models transfer friction.
    var shuttleBoardingPenalty: Double

    static let fastest = TravelProfile(
        id: "fastest", displayName: "Fastest",
        walkSpeedMetresPerSecond: 1.35,
        rainAversion: 0, slopeAversion: 0,
        allowsStairs: true, shuttleBoardingPenalty: 30
    )

    static let rainSafe = TravelProfile(
        id: "rainSafe", displayName: "Rain-safe",
        walkSpeedMetresPerSecond: 1.30,
        rainAversion: 2.5, slopeAversion: 0,
        allowsStairs: true, shuttleBoardingPenalty: 30
    )

    static let accessible = TravelProfile(
        id: "accessible", displayName: "Step-free",
        walkSpeedMetresPerSecond: 1.0,
        rainAversion: 0.5, slopeAversion: 1.5,
        allowsStairs: false, shuttleBoardingPenalty: 0
    )

    static let lazy = TravelProfile(
        id: "lazy", displayName: "Min-walk",
        walkSpeedMetresPerSecond: 1.2,
        rainAversion: 0.5, slopeAversion: 2.0,
        allowsStairs: true, shuttleBoardingPenalty: 0
    )

    static let presets: [TravelProfile] = [.fastest, .rainSafe, .accessible, .lazy]
}
