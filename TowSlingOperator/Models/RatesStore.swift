import Foundation
import Combine

/// One line of the company's own rate sheet.
///
/// Every money field is optional and stays optional. A blank is "I have not
/// answered", and $0 is "I do not charge for this" — collapsing the two would
/// tell the pricing engine a company tows for nothing.
struct RateRow: Decodable, Identifiable, Equatable {
    let serviceType: String
    let vehicleClass: String
    let asksMiles: Bool
    let asksHook: Bool
    let label: String
    var baseFee: Double?
    var hookFee: Double?
    var includedMiles: Double?
    var perMile: Double?

    var id: String { serviceType + ":" + vehicleClass }

    enum CodingKeys: String, CodingKey {
        case serviceType   = "service_type"
        case vehicleClass  = "vehicle_class"
        case asksMiles     = "asks_miles"
        case asksHook      = "asks_hook"
        case label
        case baseFee       = "base_fee"
        case hookFee       = "hook_fee"
        case includedMiles = "included_miles"
        case perMile       = "per_mile"
    }

    /// MySQL DECIMALs arrive as strings through PDO on some columns and as
    /// numbers on others. Decoded by hand so one string does not throw away
    /// the whole sheet.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serviceType   = try c.decode(String.self, forKey: .serviceType)
        vehicleClass  = try c.decode(String.self, forKey: .vehicleClass)
        asksMiles     = (try? c.decode(Bool.self, forKey: .asksMiles)) ?? true
        asksHook      = (try? c.decode(Bool.self, forKey: .asksHook)) ?? false
        label         = try c.decode(String.self, forKey: .label)
        baseFee       = RateRow.number(c, .baseFee)
        hookFee       = RateRow.number(c, .hookFee)
        includedMiles = RateRow.number(c, .includedMiles)
        perMile       = RateRow.number(c, .perMile)
    }

    private static func number(_ c: KeyedDecodingContainer<CodingKeys>,
                               _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

@MainActor
final class RatesStore: ObservableObject {

    @Published var rows: [RateRow] = []
    @Published private(set) var note: String?
    @Published private(set) var updatedAt: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var savedNote: String?

    private struct Response: Decodable {
        let rows: [RateRow]?
        let note: String?
        let updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case rows, note
            case updatedAt = "updated_at"
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await API.shared.get("/rates/mine", as: Response.self)
            rows = r.rows ?? []
            note = r.note
            updatedAt = r.updatedAt
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load your rates."
        }
    }

    /// The whole sheet goes back at once, which is what the endpoint expects.
    ///
    /// Blanks are sent as nulls rather than zeros. A company that has not
    /// answered "what do you charge for a heavy recovery" must not be recorded
    /// as charging nothing for one — that number feeds the price a customer is
    /// quoted in that whole market.
    func save() async {
        isSaving = true
        defer { isSaving = false }

        let payload: [[String: Any]] = rows.map { row in
            var d: [String: Any] = [
                "service_type":  row.serviceType,
                "vehicle_class": row.vehicleClass,
            ]
            d["base_fee"]       = row.baseFee.map { $0 as Any } ?? NSNull()
            d["hook_fee"]       = row.hookFee.map { $0 as Any } ?? NSNull()
            d["included_miles"] = row.includedMiles.map { $0 as Any } ?? NSNull()
            d["per_mile"]       = row.perMile.map { $0 as Any } ?? NSNull()
            return d
        }

        do {
            try await API.shared.postIgnoringResult("/rates/save", body: ["rows": payload])
            savedNote = "Rates saved."
            errorMessage = nil
            await load()
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not save your rates."
        }
    }
}
