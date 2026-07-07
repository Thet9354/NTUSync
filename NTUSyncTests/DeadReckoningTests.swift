import Testing
import Foundation
@testable import NTUSync

struct DeadReckoningTests {

    @Test func denialRequiresSustainedBadAccuracy() {
        var detector = GpsDenialDetector()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let justWentBad = detector.ingest(accuracy: 120, at: t0)
        let notSustainedYet = detector.ingest(accuracy: 120, at: t0.addingTimeInterval(5))
        let sustained = detector.ingest(accuracy: 120, at: t0.addingTimeInterval(10))
        let goodFixResets = detector.ingest(accuracy: 12, at: t0.addingTimeInterval(11))
        let timerRestarted = detector.ingest(accuracy: 120, at: t0.addingTimeInterval(12))
        #expect(!justWentBad)
        #expect(!notSustainedYet)
        #expect(sustained)
        #expect(!goodFixResets)
        #expect(!timerRestarted)
    }

    @Test func confidenceDecaysOnlyWhileDeadReckoning() {
        var estimator = RouteProgressEstimator(routeLengthMetres: 1000, initialConfidence: 15)
        estimator.advance(byMetres: 100)
        #expect(estimator.confidenceRadiusMetres == 15)     // GPS mode: no decay
        estimator.beginDeadReckoning()
        estimator.advance(byMetres: 100)
        #expect(abs(estimator.confidenceRadiusMetres - 23) < 0.001)  // +8% of 100 m
        #expect(estimator.distanceAlongMetres == 200)
    }

    @Test func progressClampsToRouteLength() {
        var estimator = RouteProgressEstimator(routeLengthMetres: 300)
        estimator.advance(byMetres: 500)
        #expect(estimator.distanceAlongMetres == 300)
        #expect(estimator.fractionComplete == 1)
    }

    @Test func smallDriftSnapsToFix() {
        var estimator = RouteProgressEstimator(routeLengthMetres: 1000)
        estimator.beginDeadReckoning()
        estimator.advance(byMetres: 400)
        let outcome = estimator.reconcile(fixDistanceAlong: 430, accuracy: 10)
        #expect(outcome == .snapped(driftMetres: 30))
        #expect(estimator.distanceAlongMetres == 430)
        #expect(!estimator.isDeadReckoning)
        #expect(estimator.confidenceRadiusMetres == 10)
    }

    @Test func largeDriftSuggestsReplanInsteadOfForceSnapping() {
        var estimator = RouteProgressEstimator(routeLengthMetres: 1000)
        estimator.beginDeadReckoning()
        estimator.advance(byMetres: 400)
        let outcome = estimator.reconcile(fixDistanceAlong: 520, accuracy: 10)
        #expect(outcome == .replanSuggested(driftMetres: 120))
        // Estimate is retained; the caller re-routes from the fix instead.
        #expect(estimator.distanceAlongMetres == 400)
    }
}
