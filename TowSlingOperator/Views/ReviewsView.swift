import SwiftUI

/// What customers said, unfiltered.
///
/// There is deliberately no way to hide, reply to or sort these. A rating an
/// operator can curate is worth nothing to the customer reading it, and the
/// average shown on the board is computed from these same rows either way —
/// so the only thing filtering would achieve is making this screen disagree
/// with the badge next to the company's name.
struct ReviewsView: View {
    @StateObject private var store = ReviewsStore()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading && store.company == nil {
                        ProgressView().tint(Theme.inkFaint).padding(.vertical, 50)
                    } else if let c = store.company {
                        summary(c)
                        if c.ratingCount > 0 { breakdownCard(c) }
                        listSection(c)
                    }

                    if let message = store.errorMessage {
                        Text(message)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }
                }
                .padding(16)
            }
            .refreshable { await store.load() }
        }
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    // MARK: - Pieces

    private func summary(_ c: ReviewedCompany) -> some View {
        HStack(alignment: .center, spacing: 14) {
            CompanyLogo(url: c.logoUrl, fallback: c.name, size: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(c.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if c.ratingCount > 0 {
                    HStack(spacing: 6) {
                        Stars(value: c.ratingAvg, size: 13)
                        Text(String(format: "%.1f", c.ratingAvg))
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("· \(c.ratingCount) review\(c.ratingCount == 1 ? "" : "s")")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkDim)
                    }
                } else {
                    Text("No reviews yet")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.inkDim)
                }
                Text("\(c.jobsCompleted) job\(c.jobsCompleted == 1 ? "" : "s") completed")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .cardBackground()
    }

    private func breakdownCard(_ c: ReviewedCompany) -> some View {
        VStack(spacing: 7) {
            ForEach([5, 4, 3, 2, 1], id: \.self) { n in
                let count = store.breakdown[n] ?? 0
                HStack(spacing: 9) {
                    Text("\(n) ★")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 30, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(Theme.accent)
                                .frame(width: c.ratingCount > 0
                                       ? geo.size.width * CGFloat(count) / CGFloat(c.ratingCount)
                                       : 0)
                        }
                    }
                    .frame(height: 6)

                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .cardBackground()
    }

    @ViewBuilder
    private func listSection(_ c: ReviewedCompany) -> some View {
        if c.ratingCount == 0 {
            Text("Reviews appear here when a customer rates a job you have finished.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
        } else if store.written.isEmpty {
            // Common and worth saying out loud: most people rate without
            // typing. Without this the screen looks like it failed to load.
            Text("All \(c.ratingCount) of your reviews are star ratings with no written comment.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
        } else {
            ForEach(store.written) { r in
                VStack(alignment: .leading, spacing: 5) {
                    Stars(value: Double(r.stars), size: 12)
                    if let comment = r.comment {
                        Text(comment)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(meta(r))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(padding: 13)
            }
        }
    }

    /// Month and year, never a timestamp. A review is about a company, not
    /// about a Tuesday — and an exact time narrows down who wrote it.
    private func meta(_ r: CompanyReview) -> String {
        var bits: [String] = []
        if let a = r.area, !a.isEmpty { bits.append(a) }
        if let s = r.serviceType, !s.isEmpty {
            bits.append(s.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        // One shared parser for the whole app. This screen used to guess UTC
        // while the Money screen guessed the phone's zone, so the same instant
        // printed two different answers and neither matched the server.
        let when = TowDate.monthYear(r.createdAt)
        if !when.isEmpty { bits.append(when) }
        return bits.joined(separator: " · ")
    }
}

/// Filled, half and empty stars from one Double.
struct Stars: View {
    let value: Double
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: symbol(i))
                    .font(.system(size: size))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func symbol(_ i: Int) -> String {
        let d = value - Double(i - 1)
        if d >= 0.75 { return "star.fill" }
        if d >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// A company's logo, falling back to its initial.
///
/// AsyncImage's failure and empty phases both land on the initial, so a logo
/// that 404s or has not loaded yet never leaves a blank hole where a company's
/// identity should be.
struct CompanyLogo: View {
    let url: String?
    let fallback: String
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(2).background(Color.white)
                    default:
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: some View {
        ZStack {
            Theme.accent
            Text(String(fallback.prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .heavy))
                .foregroundStyle(.white)
        }
    }
}
