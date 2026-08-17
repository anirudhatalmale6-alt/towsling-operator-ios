import SwiftUI

/// Finished work, searchable, with what it paid.
///
/// Its own screen rather than a filter on My jobs. My jobs is a worklist where
/// every row has a button; this is a record, and the questions asked of it —
/// "what did I make this week", "which job was the Silverado on the Turnpike" —
/// are nothing like "what do I do next".
struct HistoryView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var store = HistoryStore()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    filters

                    if let t = store.totals { totalsCard(t) }

                    if let message = store.errorMessage {
                        Text(message)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }

                    if store.jobs.isEmpty {
                        empty
                    } else {
                        ForEach(store.jobs) { job in
                            HistoryRow(job: job)
                        }

                        // The list is capped. Saying so beats letting somebody
                        // conclude they only ran 100 jobs this year — and the
                        // total above is the whole set either way.
                        if let t = store.totals, t.jobs > store.jobs.count {
                            Text("Showing the most recent \(store.jobs.count) of \(t.jobs). "
                               + "The totals above cover all \(t.jobs).")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { await store.load() }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "Job number, place, vehicle, plate")
        .task { if store.jobs.isEmpty { await store.load() } }
        .onChange(of: store.sessionExpired) { expired in
            if expired { Task { await session.sessionExpired() } }
        }
    }

    // MARK: - Pieces

    private var filters: some View {
        VStack(spacing: 8) {
            Picker("Period", selection: $store.range) {
                ForEach(HistoryStore.Range.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)

            Picker("Kind", selection: $store.kind) {
                ForEach(HistoryStore.Kind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func totalsCard(_ t: HistoryTotals) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("You earned")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                Spacer()
                if store.isLoading {
                    ProgressView().tint(Theme.inkFaint).scaleEffect(0.7)
                }
            }

            Text(Money.string(t.net))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.green)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Gross and fee spelled out. "You earned $924" invites "out of
            // what?", and the answer is better shown than asked for.
            Text("\(Money.string(t.gross)) billed · \(Money.string(t.fees)) platform fee")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(Theme.line)

            HStack(spacing: 0) {
                stat("\(t.paidJobs)", "paid jobs")
                stat("\(t.goaJobs)", "GOA")
                stat("\(t.canceledJobs)", "cancelled")
                stat("\(t.jobs)", "total")
            }
        }
        .cardBackground()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkFaint)
            Text(store.query.isEmpty ? "Nothing in this period" : "Nothing matches that")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(store.query.isEmpty
                 ? "Finished jobs show up here with what they paid."
                 : "Try the job number, the town, or the plate.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .cardBackground()
    }
}

private struct HistoryRow: View {
    let job: Job

    var body: some View {
        NavigationLink {
            // Read-only. The server refuses photos on a cancelled or expired
            // job anyway, so offering a camera button here would mostly be
            // offering an error message.
            JobPhotosView(jobID: job.id, title: job.callNumber, canCapture: false)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.callNumber)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(job.whereFrom)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.inkDim)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        // The settled figure, never the estimate. A finished job
                        // showing what it MIGHT have paid is how somebody is
                        // told one number and paid another.
                        if let net = job.settledNet {
                            Text(Money.string(net))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.green)
                        } else {
                            Text("—")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        Text(TowDate.short(job.completedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }

                HStack(spacing: 6) {
                    Chip(text: job.statusLabel, tone: tone)
                    Chip(text: job.serviceLabel, tone: .neutral)
                    if let v = job.vehicle, !v.isEmpty {
                        Text(v)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let n = job.photoState?.total, n > 0 {
                        Label("\(n)", systemImage: "camera.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var tone: Chip.Tone {
        switch job.status {
        case "completed": return .good
        case "goa":       return .warn
        default:          return .neutral
        }
    }
}

/// Small status pill. Its own type so History and the photo screen cannot drift
/// into two slightly different pills.
struct Chip: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone { case good, warn, neutral }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(colour)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(colour.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var colour: Color {
        switch tone {
        case .good:    return Theme.green
        case .warn:    return Theme.amber
        case .neutral: return Theme.inkDim
        }
    }
}
