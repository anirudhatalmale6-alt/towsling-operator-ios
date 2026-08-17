import Foundation
import Combine

/// GET /api/payouts/balance — mirrors towerBalance() in includes/withdrawals.php.
///
/// Five numbers, and they are not interchangeable. A company that has finished
/// four jobs today and sees "$0.00" would reasonably conclude it has not been
/// paid; the money is real, it is just still in escrow until each job settles.
/// Showing only "available" is how that support call happens.
struct Balance: Decodable {
    @Flexible var available: Double     // earned, withdrawable now
    @Flexible var inTransit: Double     // sent to the bank, not yet confirmed
    @Flexible var inEscrow: Double      // job done, not yet released
    @Flexible var lifetime: Double      // everything ever paid out
    @Flexible var feesPaid: Double
    @Flexible var min: Double

    let canWithdraw: Bool?
    let blockers: [String]?
    let bankReady: Bool?
    let payoutMode: String?
    let jobs: [PayoutRow]?

    enum CodingKeys: String, CodingKey {
        case available
        case inTransit    = "in_transit"
        case inEscrow     = "in_escrow"
        case lifetime
        case feesPaid     = "fees_paid"
        case min
        case canWithdraw  = "can_withdraw"
        case blockers
        case bankReady    = "bank_ready"
        case payoutMode   = "payout_mode"
        case jobs
    }

    /// One completed job's contribution, so the total is checkable rather than
    /// something the driver has to take on faith.
    struct PayoutRow: Decodable, Identifiable {
        let id: Int
        @Flexible var netAmount: Double
        @Flexible var grossAmount: Double
        @Flexible var platformFee: Double
        let callNumber: String?
        let serviceType: String?
        let pickupCity: String?
        let pickupState: String?
        let completedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case netAmount   = "net_amount"
            case grossAmount = "gross_amount"
            case platformFee = "platform_fee"
            case callNumber  = "call_number"
            case serviceType = "service_type"
            case pickupCity  = "pickup_city"
            case pickupState = "pickup_state"
            case completedAt = "completed_at"
        }

        var place: String {
            [pickupCity, pickupState].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

/// Field names taken from withdrawalHistory() in includes/withdrawals.php, not
/// guessed. A CodingKey that matches nothing decodes silently to nil, so a
/// wrong guess here shows an empty date forever rather than failing loudly.
struct Withdrawal: Decodable, Identifiable {
    let id: Int
    @Flexible var amount: Double
    let status: String?
    let failureReason: String?
    let requestedAt: String?
    let paidAt: String?
    /// Flexible, not Int?. COUNT(*) comes back as a real integer today because
    /// PDO runs with EMULATE_PREPARES off — but decoding Int from a JSON string
    /// THROWS rather than returning nil, so the day that setting changes the
    /// whole history list would decode to nothing and simply look empty.
    @Flexible var jobCount: Double

    enum CodingKeys: String, CodingKey {
        case id, amount, status
        case failureReason = "failure_reason"
        case requestedAt   = "requested_at"
        case paidAt        = "paid_at"
        case jobCount      = "job_count"
    }

    /// The date that matters is the one that has happened.
    var whenText: String? { paidAt ?? requestedAt }
}

@MainActor
final class MoneyStore: ObservableObject {

    @Published private(set) var balance: Balance?
    @Published private(set) var withdrawals: [Withdrawal] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var sessionExpired = false

    /// Set after a successful withdrawal so the screen can say what happened.
    @Published var lastWithdrawal: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            balance = try await API.shared.get("/payouts/balance", as: Balance.self)
            errorMessage = nil
        } catch let e as APIError {
            if e.isUnauthorized { sessionExpired = true; return }
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load your balance."
        }

        // A failure here must not blank the balance above it — the history is
        // the less important half of the screen.
        // Named for what it is. A local `HistoryResponse` would shadow the
        // file-scope one in HistoryStore — legal, and confusing to read.
        struct WithdrawalsResponse: Decodable { let withdrawals: [Withdrawal] }
        do {
            withdrawals = try await API.shared
                .get("/payouts/history", as: WithdrawalsResponse.self).withdrawals
        } catch { }
    }

    /// Take the money. The server decides whether this is allowed — the button
    /// is disabled from `can_withdraw`, but a stale screen must not be able to
    /// send a second request that pays twice.
    func withdraw() async -> String? {
        struct WithdrawResponse: Decodable {
            @Flexible var amount: Double
        }
        do {
            let r = try await API.shared.post("/payouts/withdraw", as: WithdrawResponse.self)
            lastWithdrawal = Money.string(r.amount)
            await load()
            return nil
        } catch let e as APIError {
            return e.message
        } catch {
            return "Could not send the withdrawal."
        }
    }
}
