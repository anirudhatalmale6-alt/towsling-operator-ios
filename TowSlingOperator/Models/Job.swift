import Foundation

/// One row on the board, or one of the company's own jobs.
///
/// Mirrors publicCallRow() in includes/matching.php. Anything the server chooses
/// not to send — the customer's name and exact address on an open job — is
/// optional here for the same reason it is absent there: until the job is
/// accepted, that information is not this company's to have.
struct Job: Identifiable, Decodable, Equatable {

    let id: Int
    let callNumber: String
    let status: String
    let serviceType: String
    let vehicleClass: String
    let source: String?

    // Where
    let pickupArea: String?
    let pickupCity: String?
    let pickupState: String?
    let pickupAddress: String?          // only once awarded
    let dropoffCity: String?
    let dropoffState: String?
    let dropoffAddress: String?         // only once awarded
    let towMiles: Double?
    @Flexible var distanceMiles: Double

    // What
    let vehicle: String?
    let vehicleColor: String?
    let problem: String?
    let hasKeys: Bool?
    let wheelsLock: Bool?
    let isAccident: Bool?
    let isUnderground: Bool?
    let isEV: Bool?
    let needsFlatbed: Bool?

    // Money
    @Flexible var offerAmount: Double
    @Flexible var goaAmount: Double
    @Flexible var towerNetEstimate: Double
    @Flexible var platformFeeEstimate: Double
    let isFunded: Bool?
    let surgeActive: Bool?
    @Flexible var surgeMultiplier: Double

    // Customer — present only once this company owns the job.
    let customerName: String?
    let customerPhone: String?

    // Timing
    let expiresInSec: Int?
    let canRun: Bool?

    // Settled money — present once the job is finished. These are what was
    // actually paid, not an estimate, so history shows them in preference to
    // towerNetEstimate.
    let towerNet: Double?
    let platformFee: Double?
    let awardedAmount: Double?
    let completedAt: String?

    // The photo checklist, sent with each of the company's own jobs so the
    // card can show what is still outstanding without a request per job.
    let photoState: PhotoState?
    let photos: [Photo]?

    enum CodingKeys: String, CodingKey {
        case id
        case callNumber = "call_number"
        case status
        case serviceType = "service_type"
        case vehicleClass = "vehicle_class"
        case source
        case pickupArea = "pickup_area"
        case pickupCity = "pickup_city"
        case pickupState = "pickup_state"
        case pickupAddress = "pickup_address"
        case dropoffCity = "dropoff_city"
        case dropoffState = "dropoff_state"
        case dropoffAddress = "dropoff_address"
        case towMiles = "tow_miles"
        case distanceMiles = "distance_miles"
        case vehicle
        case vehicleColor = "vehicle_color"
        case problem
        case hasKeys = "has_keys"
        case wheelsLock = "wheels_lock"
        case isAccident = "is_accident"
        case isUnderground = "is_underground"
        case isEV = "is_ev"
        case needsFlatbed = "needs_flatbed"
        case offerAmount = "offer_amount"
        case goaAmount = "goa_amount"
        case towerNetEstimate = "tower_net_estimate"
        case platformFeeEstimate = "platform_fee_estimate"
        case isFunded = "is_funded"
        case surgeActive = "surge_active"
        case surgeMultiplier = "surge_multiplier"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case expiresInSec = "expires_in_sec"
        case canRun = "can_run"
        case towerNet = "tower_net"
        case platformFee = "platform_fee"
        case awardedAmount = "awarded_amount"
        case completedAt = "completed_at"
        case photoState = "photo_state"
        case photos
    }

    // MARK: - Presentation

    /// "Hialeah, FL" — whichever of the two the server gave us.
    var whereFrom: String {
        if let a = pickupArea, !a.isEmpty { return a }
        return [pickupCity, pickupState].compactMap { $0 }.joined(separator: ", ")
    }

    var whereTo: String? {
        guard let city = dropoffCity, !city.isEmpty else { return nil }
        return [city, dropoffState].compactMap { $0 }.joined(separator: ", ")
    }

    /// What the driver actually takes home. The server works this out with the
    /// fee that will really be applied, so it is never recomputed here — a
    /// percentage guessed on the phone would promise one number at accept time
    /// and pay a different one on completion.
    var net: Double { towerNetEstimate > 0 ? towerNetEstimate : offerAmount }

    /// The hazards worth a chip on the card. Accident is left out when there is
    /// a problem line, which already says it.
    var flags: [String] {
        var out: [String] = []
        if hasKeys == false      { out.append("No keys") }
        if wheelsLock == false   { out.append("Wheels locked") }
        if isAccident == true, problem == nil { out.append("Accident") }
        if isUnderground == true { out.append("Underground") }
        if isEV == true          { out.append("EV") }
        if needsFlatbed == true  { out.append("Flatbed") }
        return out
    }

    /// The customer's own words about what is wrong, in ours.
    var problemLabel: String? {
        guard let problem else { return nil }
        switch problem {
        case "wont_start":   return "Will not start"
        case "overheated":   return "Overheated"
        case "accident":     return "Accident"
        case "flat_tire":    return "Flat tire"
        case "transmission": return "Will not go into gear"
        case "wont_move":    return "Will not move"
        case "junk":         return "Junk / scrap"
        case "other":        return "Other problem"
        default:             return problem.replacingOccurrences(of: "_", with: " ")
        }
    }

    var serviceLabel: String {
        switch serviceType {
        case "tow":            return "TOW"
        case "jumpstart":      return "JUMP"
        case "tire_change":    return "TIRE"
        case "lockout":        return "LOCKOUT"
        case "fuel_delivery":  return "FUEL"
        case "winch_recovery": return "WINCH"
        default:               return serviceType.uppercased()
        }
    }

    /// Live jobs are the ones a driver is actually working.
    static let liveStatuses = ["awarded", "en_route", "on_scene", "in_progress"]

    var isLive: Bool { Job.liveStatuses.contains(status) }

    /// What this job actually paid, once it is finished. Falls back to the
    /// estimate only while the job is still running — never afterwards, because
    /// a settled job showing an estimate is how a driver is told one number and
    /// paid another.
    var settledNet: Double? { towerNet }

    var statusLabel: String {
        switch status {
        case "completed":   return "Completed"
        case "goa":         return "Gone on arrival"
        case "canceled":    return "Cancelled"
        case "expired":     return "Expired"
        case "awarded":     return "Accepted"
        case "en_route":    return "On my way"
        case "on_scene":    return "On scene"
        case "in_progress": return "Towing"
        case "open":        return "Open"
        default:            return status.capitalized
        }
    }
}

/// The evidence checklist for one job — mirrors photoState() in includes/photos.php.
struct PhotoState: Decodable, Equatable {
    let required: Bool?
    let items: [Item]?
    let total: Int?
    let hasGOA: Bool?
    let complete: Bool?
    let pickupDone: Bool?
    let dropoffDone: Bool?
    let missingSummary: String?

    enum CodingKeys: String, CodingKey {
        case required, items, total, complete
        case hasGOA          = "has_goa"
        case pickupDone      = "pickup_done"
        case dropoffDone     = "dropoff_done"
        case missingSummary  = "missing_summary"
    }

    struct Item: Decodable, Equatable, Identifiable {
        let key: String
        let stage: String
        let label: String
        let hint: String?
        let done: Bool
        let count: Int?
        let photoID: Int?

        var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key, stage, label, hint, done, count
            case photoID = "photo_id"
        }
    }

    var doneCount: Int { (items ?? []).filter(\.done).count }
    var totalCount: Int { (items ?? []).count }
}

struct Photo: Decodable, Equatable, Identifiable {
    let id: Int
    let photoType: String
    let label: String?
    let note: String?
    let takenAt: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id, label, note, url
        case photoType = "photo_type"
        case takenAt   = "taken_at"
    }
}

/// GET /api/calls/board
struct BoardResponse: Decodable {
    let calls: [Job]
    let verification: Verification?
}

/// GET /api/calls/mine
struct MineResponse: Decodable {
    let calls: [Job]
}

/// The three things standing between a company and its first job. Sent with the
/// board so the app and the server can never disagree about why a job cannot be
/// accepted.
struct Verification: Decodable {
    let ok: Bool
    let waiting: Bool?
    let reason: String?
    let outstanding: Int?
    let steps: [Step]?

    struct Step: Decodable, Identifiable {
        let key: String
        let state: String
        let done: Bool
        let required: Bool
        let label: String
        let detail: String

        var id: String { key }
    }
}
