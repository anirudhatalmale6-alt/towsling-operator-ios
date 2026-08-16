import SwiftUI

/// One job on the board. Deliberately the same information, in the same order,
/// as the web card — an operator who uses both should not have to re-learn
/// where the number is.
struct JobCard: View {
    let job: Job
    var showAccept: Bool = true
    var onAccept: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── service, number, funded ─────────────────────────────────
            HStack(spacing: 8) {
                Text(job.serviceLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(job.callNumber)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)

                Spacer(minLength: 4)

                // Only when the money is genuinely secured. This badge is the
                // reason a company turns out, so it reads from the job rather
                // than being decoration.
                if job.isFunded == true {
                    Label("Paid job", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.green)
                        .labelStyle(.titleAndIcon)
                }
            }

            // ── route ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                Text(job.whereFrom)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let to = job.whereTo {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                    Text(to)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 9)

            if let miles = job.towMiles, miles > 0 {
                Text("\(miles, specifier: "%.1f") mi tow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.panel2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 6)
            }

            // ── what is wrong with it ───────────────────────────────────
            if let problem = job.problemLabel {
                Text(problem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.problemInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.problemBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7).stroke(Theme.problemLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(.top, 8)
            }

            // ── vehicle and hazards ─────────────────────────────────────
            Text(vehicleLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
                .padding(.top, 8)

            if !job.flags.isEmpty {
                Text(job.flags.joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 4)
            }

            Divider().overlay(Theme.line).padding(.vertical, 12)

            // ── distance, money, accept ─────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 1) {
                    Text("\(job.distanceMiles, specifier: "%.1f")")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("miles away")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                .fixedSize()

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(Money.string(job.offerAmount))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(Money.string(job.net)) to you")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                .fixedSize()

                if showAccept, let onAccept {
                    Button("Accept", action: onAccept)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .fixedSize()
                }
            }
        }
        .cardBackground()
    }

    private var vehicleLine: String {
        var parts: [String] = []
        let v = job.vehicle?.trimmingCharacters(in: .whitespaces) ?? ""
        parts.append(v.isEmpty ? "Vehicle n/a" : v)
        if let c = job.vehicleColor, !c.isEmpty { parts.append(c) }
        if let n = job.customerName, !n.isEmpty { parts.append(n) }
        return parts.joined(separator: " · ")
    }
}
