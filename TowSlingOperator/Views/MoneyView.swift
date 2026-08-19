import SwiftUI

/// What the company has earned, what is still in escrow, and the button that
/// moves it to the bank.
///
/// The headline is `available`, but the other numbers are shown beside it and
/// not behind a tap. A company that ran four jobs today and sees "$0.00" would
/// reasonably conclude it has not been paid — the money is real, it is just
/// still in escrow until each job settles, and that sentence is the difference
/// between a calm operator and a support call.
struct MoneyView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var store = MoneyStore()

    @State private var confirmingWithdraw = false
    @State private var working = false
    @State private var actionError: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if let message = store.errorMessage {
                        Text(message)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }

                    availableCard
                    if let b = store.balance { breakdown(b) }
                    if let b = store.balance, let jobs = b.jobs, !jobs.isEmpty {
                        jobsCard(jobs)
                    }
                    if !store.withdrawals.isEmpty { withdrawalsCard }
                }
                .padding(16)
            }
            .refreshable { await store.load() }
        }
        .navigationTitle("Money")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .onChange(of: store.sessionExpired) { expired in
            if expired { Task { await session.sessionExpired() } }
        }
        .alert("Withdraw \(Money.string(store.balance?.available ?? 0))?",
               isPresented: $confirmingWithdraw) {
            Button("Cancel", role: .cancel) { }
            Button("Withdraw") { send() }
        } message: {
            Text("This sends everything available to the bank account on your "
               + "Stripe profile. It usually lands in one to two business days.")
        }
        .alert("Could not withdraw",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .alert(store.lastWithdrawal?.title ?? "On its way",
               isPresented: Binding(get: { store.lastWithdrawal != nil },
                                    set: { if !$0 { store.lastWithdrawal = nil } })) {
            Button("OK", role: .cancel) { store.lastWithdrawal = nil }
        } message: {
            Text(store.lastWithdrawal?.body ?? "")
        }
    }

    // MARK: - Pieces

    private var availableCard: some View {
        VStack(spacing: 6) {
            Text("Available to withdraw")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkDim)

            Text(Money.string(store.balance?.available ?? 0))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .redacted(reason: store.balance == nil ? .placeholder : [])

            if let b = store.balance {
                if b.canWithdraw == true {
                    Button {
                        confirmingWithdraw = true
                    } label: {
                        if working { ProgressView().tint(.white) }
                        else { Text("Withdraw to my bank") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(working)
                    .padding(.top, 6)
                } else if let blockers = b.blockers, !blockers.isEmpty {
                    // Why the button is not there, in the order they would hit
                    // them. "Withdraw" greyed out with no reason is the single
                    // most common way a payout screen loses somebody's trust.
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(blockers, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.amber)
                                Text(reason)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.inkDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }

                if b.payoutMode == "auto" {
                    Text("Automatic payouts are on — this goes out on its own.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .cardBackground()
    }

    private func breakdown(_ b: Balance) -> some View {
        VStack(spacing: 0) {
            row("In escrow", b.inEscrow,
                note: "Jobs you have done that have not been released yet.")
            Divider().background(Theme.line)
            row("Sent to bank", b.inTransit,
                note: "On its way. One to two business days.")
            Divider().background(Theme.line)
            row("Paid out, all time", b.lifetime, note: nil)
            Divider().background(Theme.line)
            row("Platform fees, all time", b.feesPaid, note: nil, dim: true)
        }
        .cardBackground(padding: 0)
    }

    private func row(_ label: String, _ amount: Double,
                     note: String?, dim: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dim ? Theme.inkDim : Theme.ink)
                Spacer()
                Text(Money.string(amount))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(dim ? Theme.inkDim : Theme.ink)
            }
            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private func jobsCard(_ jobs: [Balance.PayoutRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What makes up your balance")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkDim)

            ForEach(jobs) { j in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(j.callNumber ?? "Job")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if !j.place.isEmpty {
                            Text(j.place)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Money.string(j.netAmount))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.green)
                        // Gross and fee under the net, because "why is this $99
                        // and not $110" is the question this screen exists to
                        // answer before it gets asked.
                        Text("\(Money.string(j.grossAmount)) − \(Money.string(j.platformFee)) fee")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var withdrawalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Withdrawals")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkDim)

            ForEach(store.withdrawals) { w in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TowDate.short(w.whenText))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(statusLine(w))
                            .font(.system(size: 11.5))
                            .foregroundStyle(w.status == "failed" ? Theme.amber : Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(Money.string(w.amount))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func statusLine(_ w: Withdrawal) -> String {
        let n = Int(w.jobCount)
        let jobs = n > 0 ? "\(n) job\(n == 1 ? "" : "s") · " : ""
        switch w.status {
        case "paid":    return jobs + "Paid"
        case "pending": return jobs + "On its way"
        // The reason, not just the word. "Failed" on its own leaves somebody
        // ringing us to find out that their bank details were rejected.
        case "failed":  return jobs + "Failed — " + (w.failureReason ?? "check your bank details")
        default:        return jobs + (w.status ?? "")
        }
    }

    private func send() {
        working = true
        Task {
            let err = await store.withdraw()
            working = false
            if let err { actionError = err }
        }
    }
}

/// Every timestamp the app prints goes through here.
///
/// The API sends ISO-8601 with a real offset ("2026-08-17T14:31:02-07:00").
/// That matters: the server runs on Pacific time, so the old parser — which
/// read a bare "2026-08-17 14:31:02" as the *phone's* zone — showed a driver
/// in Florida every time three hours behind his own watch. With the offset
/// present, the instant is unambiguous and the display formatter renders it
/// wherever the driver happens to be standing.
///
/// The legacy shape is still accepted so a phone running this build against
/// an older server, or any single field that slips through bare, degrades to
/// the previous behaviour instead of showing a dash.
enum TowDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Bare MySQL DATETIME, read in the zone the server writes in.
    private static let legacy: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        f.timeZone = TimeZone.current       // the reader's clock, not the server's
        return f
    }()

    private static let monthYearFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.timeZone = TimeZone.current
        return f
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return iso.date(from: raw) ?? isoFractional.date(from: raw) ?? legacy.date(from: raw)
    }

    static func short(_ raw: String?) -> String {
        guard let d = date(raw) else { return "—" }
        return display.string(from: d)
    }

    /// Month and year only — used where a precise time would identify a person.
    static func monthYear(_ raw: String?) -> String {
        guard let d = date(raw) else { return "" }
        return monthYearFmt.string(from: d)
    }
}
