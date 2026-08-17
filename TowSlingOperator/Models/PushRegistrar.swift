import Foundation
import UIKit
import UserNotifications

/// Asking for notification permission, and handing the device token to the API.
///
/// The whole point of this app is that a job appears and somebody turns out for
/// it within twenty minutes. A driver who has to keep opening the app to check
/// is the case push exists to remove.
@MainActor
final class PushRegistrar: NSObject, ObservableObject {

    static let shared = PushRegistrar()

    @Published private(set) var authorized = false
    @Published private(set) var lastError: String?

    /// Held until somebody is signed in — a token is useless without an account
    /// to attach it to, and iOS often hands it over before sign-in finishes.
    private var pendingToken: String?
    private var isSignedIn = false

    // MARK: - Permission

    /// Asked AFTER sign-in, never on first launch.
    ///
    /// The prompt can only be shown once. Spent on the launch screen, before
    /// the operator has seen a single job, it gets refused — and a refusal is
    /// final: nothing in the app can ask again, only a trip to Settings. Asked
    /// once he is signed in and looking at jobs, the request explains itself.
    func requestIfNeeded() async {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let ok = try await centre.requestAuthorization(options: [.alert, .sound, .badge])
                authorized = ok
                if ok { UIApplication.shared.registerForRemoteNotifications() }
            } catch {
                lastError = error.localizedDescription
            }
        case .denied:
            authorized = false
        default:
            authorized = true
            // Re-register every launch. Tokens change — a restore from backup,
            // an OS update — and the old one silently stops working.
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Token

    func signedIn() {
        isSignedIn = true
        if let token = pendingToken { Task { await send(token) } }
    }

    func signedOut() {
        isSignedIn = false
        pendingToken = nil
    }

    func received(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = hex
        guard isSignedIn else { return }      // sent the moment sign-in lands
        Task { await send(hex) }
    }

    func failed(_ error: Error) {
        lastError = error.localizedDescription
    }

    private func send(_ token: String) async {
        do {
            try await API.shared.postIgnoringResult("/push/register-ios", body: [
                "device_token": token,
                "environment": Self.apnsEnvironment,
                "device_name": UIDevice.current.name,
                "label": UIDevice.current.name,
            ])
            pendingToken = nil
            lastError = nil
        } catch {
            // Kept, so the next sign-in or foreground retries it.
            lastError = (error as? APIError)?.message ?? "Could not register for alerts."
        }
    }

    // MARK: - Which Apple do we belong to

    /// "sandbox" or "production", read from the embedded provisioning profile.
    ///
    /// This matters more than it sounds. A build run from Xcode onto a phone
    /// gets a SANDBOX device token, and sending one to Apple's production host
    /// comes back BadDeviceToken — no alert, no error the driver can see, and
    /// identical in every visible way to push simply not working. It is the
    /// single commonest reason a correct implementation appears dead on the one
    /// device the developer is holding.
    ///
    /// `#if DEBUG` is the usual shortcut and it is wrong for a Release build run
    /// from Xcode, which still signs with a development profile. The profile
    /// itself is the only thing that actually knows.
    static let apnsEnvironment: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // It is CMS-wrapped binary with a plist in the middle; scanning
              // for the key is far more robust than trying to decode the
              // signature envelope.
              let text = String(data: data, encoding: .isoLatin1)
        else {
            // No profile embedded = an App Store build. Those are production.
            return "production"
        }

        if let range = text.range(of: "<key>aps-environment</key>") {
            let after = text[range.upperBound...].prefix(120)
            if after.contains("development") { return "sandbox" }
        }
        return "production"
    }()
}
