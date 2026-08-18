import Foundation
import Combine

/// What this company gets woken up for.
///
/// Every field here is a way to receive FEWER jobs, which makes this the most
/// dangerous screen in the app: a payout floor typed in the wrong box, or quiet
/// hours left over from a holiday, and the operator concludes there is no work
/// about rather than that he switched it off. So each control says what it
/// costs him, and the screen refuses to imply alerts are on when they are not.
struct AlertPrefs: Decodable, Equatable {
    var enabled: Bool
    /// nil means "use my service radius" — one number to keep right instead of
    /// two that quietly drift apart.
    var radiusMiles: Int?
    var serviceRadius: Int
    @Flexible var minPayout: Double
    /// "HH:mm" or nil. Set as a pair or cleared as a pair; half a window is not
    /// a window, and storing one half means "never quiet" without saying so.
    var quietStart: String?
    var quietEnd: String?
    var timezone: String?
    var is247: Bool
    /// Whether a yard location exists at all. Without one the server falls back
    /// to the state centroid, and the operator sees jobs from the wrong end of
    /// Florida without ever being told why.
    var baseSet: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case radiusMiles   = "radius_miles"
        case serviceRadius = "service_radius"
        case minPayout     = "min_payout"
        case quietStart    = "quiet_start"
        case quietEnd      = "quiet_end"
        case timezone
        case is247         = "is_24_7"
        case baseSet       = "base_set"
    }
}

struct PushDevice: Decodable, Identifiable, Equatable {
    let id: Int
    let platform: String?
    let label: String?
    let active: Bool
    let failCount: Int?
    let lastSuccess: String?
    let lastError: String?
    let registeredAt: String?
    /// "ok", "untested", "stopped", "not_installed".
    let health: String?
    /// "apns" for this app, "webpush" for the dashboard in a browser.
    let transport: String?

    enum CodingKeys: String, CodingKey {
        case id, platform, label, active, health, transport
        case failCount    = "fail_count"
        case lastSuccess  = "last_success"
        case lastError    = "last_error"
        case registeredAt = "registered_at"
    }

    var isThisApp: Bool { transport == "apns" }

    var healthLabel: String {
        switch health {
        case "ok":            return "Working"
        case "untested":      return "Not tested yet"
        case "stopped":       return "Stopped"
        case "not_installed": return "Browser only — will not deliver"
        default:              return "Unknown"
        }
    }
}

@MainActor
final class AlertsStore: ObservableObject {

    @Published var prefs: AlertPrefs?
    @Published private(set) var devices: [PushDevice] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var savedNote: String?

    private struct PrefsResponse: Decodable { let prefs: AlertPrefs? }
    private struct DevicesResponse: Decodable { let devices: [PushDevice]? }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await API.shared.get("/push/prefs", as: PrefsResponse.self)
            guard let loaded = p.prefs else {
                errorMessage = "Could not read your alert settings."
                return
            }
            prefs = loaded
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
            return
        } catch {
            errorMessage = "Could not load your alert settings."
            return
        }

        // Devices are useful but not essential — a failure here must not blank
        // the settings that did load.
        if let d = try? await API.shared.get("/push/devices", as: DevicesResponse.self) {
            devices = d.devices ?? []
        }
    }

    /// Saves exactly the fields given. The endpoint reads each key with
    /// array_key_exists, so sending only what changed leaves the rest alone —
    /// and means a screen that has not loaded yet can never blank a setting.
    func save(_ body: [String: Any], note: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await API.shared.postIgnoringResult("/push/prefs", body: body)
            savedNote = note
            errorMessage = nil
            await load()
        } catch let e as APIError {
            errorMessage = e.message
            // Put the screen back to what the server actually holds. Leaving a
            // rejected value sitting in the control is how somebody walks away
            // believing a setting saved.
            await load()
        } catch {
            errorMessage = "Could not save that."
            await load()
        }
    }

    /// Send a real notification to this phone.
    func sendTest() async {
        do {
            try await API.shared.postIgnoringResult("/push/test", body: [:])
            savedNote = "Test alert sent. It should arrive within a few seconds."
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not send a test alert."
        }
    }
}
