import Foundation
import Combine

/// The company's own record.
///
/// Every capability flag comes back from MySQL as 0/1 rather than true/false,
/// so they are decoded as Int and exposed as Bool. Declaring them Bool would
/// throw on the first field and lose the entire screen.
struct Company: Decodable, Equatable {
    let id: Int
    let name: String
    let legalName: String?
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let verificationStatus: String?
    let dotNumber: String?
    let mcNumber: String?
    let serviceRadiusMiles: Int?
    let baseLat: Double?
    let baseLng: Double?
    let trucksCount: Int?
    let emailVerified: Bool?
    let phoneVerified: Bool?

    private let hasLightDuty: Int?
    private let hasMediumDuty: Int?
    private let hasHeavyDuty: Int?
    private let hasFlatbed: Int?
    private let hasWheelLift: Int?
    private let hasWinchRecovery: Int?
    private let hasLockout: Int?
    private let hasJumpstart: Int?
    private let hasTireChange: Int?
    private let hasFuelDelivery: Int?
    private let hasMotorcycle: Int?
    private let hasEVCertified: Int?
    private let hasLowClearance: Int?
    private let is247Raw: Int?
    private let isAvailableRaw: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, address, city, state, zip
        case legalName          = "legal_name"
        case verificationStatus = "verification_status"
        case dotNumber          = "dot_number"
        case mcNumber           = "mc_number"
        case serviceRadiusMiles = "service_radius_miles"
        case baseLat            = "base_lat"
        case baseLng            = "base_lng"
        case trucksCount        = "trucks_count"
        case emailVerified      = "email_verified"
        case phoneVerified      = "phone_verified"
        case hasLightDuty       = "has_light_duty"
        case hasMediumDuty      = "has_medium_duty"
        case hasHeavyDuty       = "has_heavy_duty"
        case hasFlatbed         = "has_flatbed"
        case hasWheelLift       = "has_wheel_lift"
        case hasWinchRecovery   = "has_winch_recovery"
        case hasLockout         = "has_lockout"
        case hasJumpstart       = "has_jumpstart"
        case hasTireChange      = "has_tire_change"
        case hasFuelDelivery    = "has_fuel_delivery"
        case hasMotorcycle      = "has_motorcycle"
        case hasEVCertified     = "has_ev_certified"
        case hasLowClearance    = "has_lowclearance"
        case is247Raw           = "is_24_7"
        case isAvailableRaw     = "is_available"
    }

    var is247: Bool { (is247Raw ?? 0) == 1 }
    var isAvailable: Bool { (isAvailableRaw ?? 1) == 1 }
    var baseSet: Bool { baseLat != nil && baseLng != nil }

    /// In the order an operator thinks about them: what size, then what kind.
    var capabilities: [(label: String, on: Bool)] {
        [("Light duty",     (hasLightDuty ?? 0) == 1),
         ("Medium duty",    (hasMediumDuty ?? 0) == 1),
         ("Heavy duty",     (hasHeavyDuty ?? 0) == 1),
         ("Flatbed",        (hasFlatbed ?? 0) == 1),
         ("Wheel lift",     (hasWheelLift ?? 0) == 1),
         ("Winch recovery", (hasWinchRecovery ?? 0) == 1),
         ("Lockout",        (hasLockout ?? 0) == 1),
         ("Jump start",     (hasJumpstart ?? 0) == 1),
         ("Tyre change",    (hasTireChange ?? 0) == 1),
         ("Fuel delivery",  (hasFuelDelivery ?? 0) == 1),
         ("Motorcycle",     (hasMotorcycle ?? 0) == 1),
         ("EV certified",   (hasEVCertified ?? 0) == 1),
         ("Low clearance",  (hasLowClearance ?? 0) == 1)]
    }
}

struct Truck: Decodable, Identifiable, Equatable {
    let id: Int
    var label: String
    var truckType: String
    var capacityClass: String
    var make: String?
    var model: String?
    var year: Int?
    var plate: String?
    var equipment: [String]
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, label, make, model, year, plate, equipment, notes
        case truckType     = "truck_type"
        case capacityClass = "capacity_class"
    }

    var describedType: String {
        truckType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct VerificationStep: Decodable, Identifiable, Equatable {
    let key: String
    let state: String?
    let done: Bool
    /// Named isRequired, not `required` — that is a declaration modifier in
    /// Swift and using it as a property name is the kind of thing that compiles
    /// today and stops compiling on a toolchain upgrade.
    let isRequired: Bool?
    let label: String
    let detail: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, state, done, label, detail
        case isRequired = "required"
    }
}

struct CompanyVerification: Decodable, Equatable {
    let ok: Bool
    let reason: String?
    let steps: [VerificationStep]?
    let outstanding: Int?
}

@MainActor
final class CompanyStore: ObservableObject {

    @Published private(set) var company: Company?
    @Published private(set) var trucks: [Truck] = []
    @Published private(set) var verification: CompanyVerification?
    @Published private(set) var truckTypes: [String] = []
    @Published private(set) var equipmentTypes: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var savedNote: String?

    /// Held separately from `company` so the switch can move the instant it is
    /// tapped. A toggle that waits for a round trip before it moves reads as
    /// broken, and an operator going off duty taps it again — turning himself
    /// back on.
    @Published var availableLocal: Bool = true

    private struct Response: Decodable {
        let company: Company?
        let trucks: [Truck]?
        let truckTypes: [String]?
        let equipment: [String]?
        let verification: CompanyVerification?
        enum CodingKeys: String, CodingKey {
            case company, trucks, equipment, verification
            case truckTypes = "truck_types"
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await API.shared.get("/company/overview", as: Response.self)
            guard let c = r.company else {
                errorMessage = "Could not read your company record."
                return
            }
            company = c
            availableLocal = c.isAvailable
            trucks = r.trucks ?? []
            truckTypes = r.truckTypes ?? []
            equipmentTypes = r.equipment ?? []
            verification = r.verification
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load your company."
        }
    }

    /// The duty switch.
    ///
    /// Off means this company is not OFFERED work — no alerts, and it stops
    /// counting as coverage for a customer looking for a truck nearby. It does
    /// not hide the board or block accepting: someone who flips back on should
    /// not have to wait for the next alert to earn.
    func setAvailable(_ on: Bool) async {
        availableLocal = on
        do {
            try await API.shared.postIgnoringResult("/company/availability", body: ["available": on])
            savedNote = on ? "You are on duty — jobs will be offered to you."
                           : "You are off duty. You will not be offered jobs, but you can still take one from the board."
            errorMessage = nil
            await load()
        } catch let e as APIError {
            errorMessage = e.message
            availableLocal = company?.isAvailable ?? true    // put the switch back
        } catch {
            errorMessage = "Could not change your duty status."
            availableLocal = company?.isAvailable ?? true
        }
    }

    func saveTruck(_ truck: Truck, isNew: Bool) async {
        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = [
            "label":          truck.label,
            "truck_type":     truck.truckType,
            "capacity_class": truck.capacityClass,
            "equipment":      truck.equipment,
        ]
        if !isNew { body["id"] = truck.id }
        if let v = truck.make,  !v.isEmpty { body["make"] = v }
        if let v = truck.model, !v.isEmpty { body["model"] = v }
        if let v = truck.plate, !v.isEmpty { body["plate"] = v }
        if let v = truck.notes, !v.isEmpty { body["notes"] = v }
        if let y = truck.year { body["year"] = y }

        do {
            try await API.shared.postIgnoringResult("/company/truck-save", body: body)
            savedNote = isNew ? "Truck added." : "Truck saved."
            errorMessage = nil
            await load()
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not save that truck."
        }
    }

    func deleteTruck(_ truck: Truck) async {
        do {
            try await API.shared.postIgnoringResult("/company/truck-delete", body: ["id": truck.id])
            savedNote = "Truck removed."
            errorMessage = nil
            await load()
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not remove that truck."
        }
    }
}
