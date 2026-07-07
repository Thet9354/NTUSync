import Foundation
import CoreLocation
import CoreMotion
import os

/// Battery-tiered accuracy policy (§5.2 of the design spec).
nonisolated enum LocationTier: Sendable {
    case idle        // no active trip: reduced accuracy
    case cruise      // walking between decision points
    case precision   // within ~120 m of a stop or turn

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .idle: kCLLocationAccuracyReduced
        case .cruise: kCLLocationAccuracyHundredMeters
        case .precision: kCLLocationAccuracyBest
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .idle: 100
        case .cruise: 25
        case .precision: 5
        }
    }
}

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var denialDetector = GpsDenialDetector()

    private(set) var lastFix: GeoPoint?
    private(set) var lastAccuracy: Double = -1
    private(set) var isGPSDenied = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var tier: LocationTier = .idle

    override init() {
        super.init()
        manager.delegate = self
        apply(tier: .idle)
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    func setTier(_ tier: LocationTier) {
        guard tier != self.tier else { return }
        self.tier = tier
        apply(tier: tier)
        Logger.location.info("location tier -> \(String(describing: tier))")
    }

    private func apply(tier: LocationTier) {
        manager.desiredAccuracy = tier.desiredAccuracy
        manager.distanceFilter = tier.distanceFilter
    }

    // MARK: CLLocationManagerDelegate (delivered on the main run loop)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let point = GeoPoint(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude)
        let accuracy = latest.horizontalAccuracy
        let timestamp = latest.timestamp
        Task { @MainActor in
            self.lastFix = point
            self.lastAccuracy = accuracy
            let denied = self.denialDetector.ingest(accuracy: accuracy, at: timestamp)
            if denied != self.isGPSDenied {
                self.isGPSDenied = denied
                Logger.location.notice("gps \(denied ? "denied -> dead reckoning engaged" : "reacquired")")
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            Logger.location.info("authorization \(String(describing: status.rawValue))")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.location.error("location failure: \(error.localizedDescription)")
    }
}

@MainActor
@Observable
final class PedometerService {
    private let pedometer = CMPedometer()
    private(set) var steps = 0
    private(set) var distanceMetres: Double = 0
    private(set) var isRunning = false

    var onUpdate: ((_ steps: Int, _ distanceDelta: Double) -> Void)?
    private var lastReportedDistance: Double = 0

    func start() {
        guard CMPedometer.isStepCountingAvailable() else {
            Logger.motion.notice("step counting unavailable on this device")
            return
        }
        guard !isRunning else { return }
        isRunning = true
        lastReportedDistance = 0
        pedometer.startUpdates(from: .now) { [weak self] data, error in
            if let error {
                Logger.motion.error("pedometer failure: \(error.localizedDescription)")
                return
            }
            guard let data else { return }
            let steps = data.numberOfSteps.intValue
            let distance = data.distance?.doubleValue ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.steps = steps
                let delta = distance - self.lastReportedDistance
                self.lastReportedDistance = distance
                self.distanceMetres = distance
                if delta > 0 { self.onUpdate?(steps, delta) }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        pedometer.stopUpdates()
        isRunning = false
        Logger.motion.info("pedometer stopped at \(self.steps) steps")
    }
}
