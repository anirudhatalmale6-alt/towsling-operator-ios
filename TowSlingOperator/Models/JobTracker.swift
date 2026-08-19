import Foundation
import CoreLocation
import UIKit
import Combine

/// Sending this truck's position to the customer watching it, for one job.
///
/// Not to be confused with `LocationReporter`, which answers a different
/// question with a different budget:
///
///   LocationReporter — "roughly where is this phone, so we can offer it work?"
///                      One position, overwritten, ~every 2 minutes, 100m
///                      accuracy, running whenever the operator is signed in.
///
///   JobTracker      — "where is this truck RIGHT NOW, for the customer who is
///                      standing on a hard shoulder watching a map?" Best
///                      accuracy, every few seconds, running ONLY between
///                      accepting a job and finishing it.
///
/// The second one is expensive — it holds the GPS chip open — which is exactly
/// why it is scoped to a live job and shuts itself down the moment the server
/// says the job is over. A tracker left running after a job is a battery
/// complaint, an App Store rejection, and a driver being followed around all
/// evening for no reason.
///
/// The server is the authority on both cadence and lifetime: every ping answers
/// with `next_ping_seconds` and `keep_tracking`. This class does not decide when
/// to stop, it obeys.
@MainActor
final class JobTracker: NSObject, ObservableObject {

    static let shared = JobTracker()

    /// The job being tracked, if any. Published so a view can show the driver
    /// that his position is being shared — which is both honest and required.
    @Published private(set) var trackingCallID: Int?
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var lastError: String?
    /// Set when the phone will only ever report in the foreground, so the UI can
    /// tell the driver his customer's map freezes when he switches apps —
    /// something he would otherwise only discover from an angry phone call.
    @Published private(set) var foregroundOnly = false

    private let manager = CLLocationManager()

    /// Server-dictated. Seeded with the documented default so the first
    /// interval is sane before any reply has landed.
    private var minimumInterval: TimeInterval = 10
    private var lastSent: Date?
    private var inFlight = false

    private override init() {
        super.init()
        manager.delegate = self
        // The customer is watching a marker against street geometry. Hundred
        // metre accuracy puts the truck on the wrong side of a dual
        // carriageway, which is the difference between "he has passed me" and
        // "he is pulling in".
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Report every 25 metres rather than on a pure timer: a truck sitting
        // at a light should not spend battery restating the same coordinate,
        // and one moving fast should not wait out a fixed interval.
        manager.distanceFilter = 25
        // iOS pauses updates when it decides you have stopped moving, and
        // resuming is not guaranteed to be prompt. For a driver stuck in
        // traffic that reads to the customer as a frozen map.
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Lifecycle

    /// Called whenever the operator's live jobs change. Idempotent: safe to
    /// call on every board refresh with the same job.
    func sync(activeCallID: Int?) {
        guard let id = activeCallID else { stop(); return }
        if trackingCallID == id { return }
        start(callID: id)
    }

    private func start(callID: Int) {
        trackingCallID = callID
        lastSent = nil
        lastError = nil

        switch manager.authorizationStatus {
        case .authorizedAlways:
            foregroundOnly = false
            // Only legal with the `location` background mode declared, and only
            // meaningful with Always. Without it, every position stops the
            // instant the driver switches to Maps — which is the first thing he
            // does after accepting.
            manager.allowsBackgroundLocationUpdates = true
            // The blue bar. Apple requires the driver be able to see that this
            // is happening, and so do I.
            manager.showsBackgroundLocationIndicator = true
        case .authorizedWhenInUse:
            foregroundOnly = true
            manager.allowsBackgroundLocationUpdates = false
        default:
            // No permission, nothing to do. The customer's map falls back to
            // the coarse position the matching layer already has.
            trackingCallID = nil
            return
        }

        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stop() {
        guard trackingCallID != nil else { return }
        trackingCallID = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - Sending

    private func send(_ fix: CLLocation) async {
        guard let callID = trackingCallID else { return }

        // One in flight at a time. On bad signal a 20-second request plus a
        // 25-metre distance filter is how you queue eleven pings that all land
        // at once, out of order, and get thrown away by the server's
        // out-of-order guard.
        if inFlight { return }
        if let last = lastSent, Date().timeIntervalSince(last) < minimumInterval { return }

        inFlight = true
        defer { inFlight = false }
        lastSent = Date()

        struct PingResponse: Decodable {
            let keepTracking: Bool?
            let nextPingSeconds: Int?
            enum CodingKeys: String, CodingKey {
                case keepTracking    = "keep_tracking"
                case nextPingSeconds = "next_ping_seconds"
            }
        }

        var body: [String: Any] = [
            "call_id": callID,
            "lat": fix.coordinate.latitude,
            "lng": fix.coordinate.longitude,
            "recorded_at": Int(fix.timestamp.timeIntervalSince1970),
        ]
        if fix.horizontalAccuracy > 0 { body["accuracy_m"] = Int(fix.horizontalAccuracy.rounded()) }
        // Negative means "unknown" in CoreLocation, not "zero" — sending it as a
        // number would point the marker due north and stop the truck dead.
        if fix.course >= 0 { body["heading"] = Int(fix.course.rounded()) }
        if fix.speed >= 0 { body["speed_mph"] = fix.speed * 2.236936 }

        do {
            let r = try await API.shared.post("/tracking/ping", body: body, as: PingResponse.self)
            lastSentAt = Date()
            lastError = nil
            if let secs = r.nextPingSeconds { minimumInterval = max(4, TimeInterval(secs)) }
            // The job is finished, cancelled, or no longer his. Shut the GPS
            // down rather than retrying — the server has told us there is
            // nothing left to report.
            if r.keepTracking == false { stop() }
        } catch let e as APIError {
            lastError = e.message
            // A refusal that will not fix itself on the next fix: stop, rather
            // than hold the GPS open arguing with the server all afternoon.
            if e.isUnauthorized { stop() }
            lastSent = nil
        } catch {
            // Ordinary connectivity. Keep the tracker running and let the next
            // fix try again — a driver in a dead spot comes back.
            lastError = "Could not send your position."
            lastSent = nil
        }
    }
}

extension JobTracker: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        // Same floor the server enforces at tracking_max_accuracy_m: a fix it
        // will refuse to move the marker for is not worth the request.
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 250 else { return }
        Task { @MainActor in await self.send(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            // Permission can be granted or revoked mid-job, from Settings,
            // while a customer is watching the map.
            guard let id = self.trackingCallID else { return }
            self.stop()
            self.start(callID: id)
        }
    }
}
