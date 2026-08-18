import Foundation
import CoreLocation
import UIKit
import Combine

/// Telling the server roughly where this phone is, so jobs are matched against
/// the truck rather than the yard.
///
/// Deliberately coarse and deliberately cheap. This is not tracking: it is not
/// a trail, it is not per-second, and it stops entirely when the operator signs
/// out. One position, overwritten, used to answer "is this phone near that job".
/// The per-job live tracking a customer watches is a separate thing with a
/// separate permission and a separate switch.
///
/// Two sources, in order of preference:
///   • Significant location change — the cheap one. iOS reports roughly every
///     500m/5 minutes, using cell towers rather than GPS, and will wake a
///     suspended app to do it. This is what makes the feature work while the
///     phone is in a pocket.
///   • Foreground refresh — a single fix whenever the app comes to the front.
///     This alone is enough for a driver who opens the app between jobs, and it
///     is all that is available if only "When In Use" was granted.
@MainActor
final class LocationReporter: NSObject, ObservableObject {

    static let shared = LocationReporter()

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var lastError: String?
    /// Mirrors the server's per-device switch so the Alerts screen can show it
    /// without a round trip on every appearance.
    @Published var useDeviceLocation = true

    private let manager = CLLocationManager()
    private var isSignedIn = false
    /// The APNs token identifies which device row to update. Without it there is
    /// nothing to attach a position to, so nothing is sent.
    private var deviceToken: String?

    /// Don't hammer the endpoint. Significant-change fires on its own schedule
    /// and the foreground hook fires on every app switch; both can arrive
    /// seconds apart while the truck has not moved.
    private var lastSent: Date?
    private static let minimumInterval: TimeInterval = 120

    private override init() {
        super.init()
        manager.delegate = self
        // Matching a job to a truck does not need street-level accuracy, and
        // asking for it would run the GPS chip all day for no benefit anybody
        // can see. A hundred metres is far below the mile the radius works in.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }

    // MARK: - Lifecycle

    func signedIn(deviceToken: String?) {
        isSignedIn = true
        if let deviceToken { self.deviceToken = deviceToken }
        start()
    }

    func signedOut() {
        isSignedIn = false
        deviceToken = nil
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// Called by PushRegistrar the moment a token exists — a position with no
    /// device to attach it to is nothing.
    func tokenArrived(_ token: String) {
        deviceToken = token
        if isSignedIn { start() }
    }

    /// Asked only when the operator turns the switch on, never on launch.
    ///
    /// Location is the permission people refuse hardest and iOS only asks once.
    /// Spent before the driver knows what it buys him, it is refused, and the
    /// refusal cannot be undone from inside the app.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Upgrading to Always is what lets a pocketed phone keep reporting.
            // Asked second, and only after When In Use is already granted —
            // Apple requires that order and refuses the prompt otherwise.
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start() {
        guard isSignedIn, useDeviceLocation, deviceToken != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation()
        case .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    /// Called when the app comes to the front.
    func refresh() {
        guard isSignedIn, useDeviceLocation, deviceToken != nil else { return }
        guard manager.authorizationStatus == .authorizedAlways
           || manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestLocation()
    }

    /// Flipping the switch off tells the server immediately, so a phone that is
    /// about to stop reporting does not sit there with a position from an hour
    /// ago being treated as current.
    func setUseDeviceLocation(_ on: Bool) {
        useDeviceLocation = on
        if on {
            requestPermission()
            start()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            Task { await sendSwitchOnly(false) }
        }
    }

    // MARK: - Sending

    private func send(_ location: CLLocation, force: Bool = false) async {
        guard let deviceToken else { return }
        if !force, let last = lastSent, Date().timeIntervalSince(last) < Self.minimumInterval {
            return
        }
        lastSent = Date()

        do {
            try await API.shared.postIgnoringResult("/push/location", body: [
                "device_token": deviceToken,
                "lat": location.coordinate.latitude,
                "lng": location.coordinate.longitude,
                "accuracy_m": Int(location.horizontalAccuracy.rounded()),
                "use_device_location": useDeviceLocation,
            ])
            lastSentAt = Date()
            lastError = nil
        } catch {
            // Never surfaced as an alert. Failing to report a position costs the
            // driver nothing immediately — the server falls back to the yard —
            // and a popup about it while he is driving would be worse than the
            // problem.
            lastError = (error as? APIError)?.message ?? "Could not update your location."
            lastSent = nil                  // let the next fix try again
        }
    }

    private func sendSwitchOnly(_ on: Bool) async {
        guard let deviceToken, let fix = manager.location else { return }
        do {
            try await API.shared.postIgnoringResult("/push/location", body: [
                "device_token": deviceToken,
                "lat": fix.coordinate.latitude,
                "lng": fix.coordinate.longitude,
                "use_device_location": on,
            ])
        } catch {
            lastError = (error as? APIError)?.message
        }
    }
}

extension LocationReporter: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorization = status
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        // A fix the phone is not confident in is worse than none: a 3km-accurate
        // position can put a truck on the wrong side of a city and quietly
        // change which jobs it is told about.
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy < 2000 else { return }
        Task { @MainActor in await self.send(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
        }
    }
}
