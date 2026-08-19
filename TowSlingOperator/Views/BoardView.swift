import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var board: BoardStore

    @State private var accepting: Job?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {

                    if let v = board.verification, v.ok == false {
                        VerificationBanner(verification: v)
                    }

                    if let message = board.errorMessage {
                        Text(message)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }

                    header

                    if board.jobs.isEmpty {
                        EmptyBoard(loading: board.isLoading)
                    } else {
                        ForEach(board.jobs) { job in
                            JobCard(job: job, showAccept: canAccept) {
                                accepting = job
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { await board.refresh() }
        }
        .navigationTitle("Available jobs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $accepting) { job in
            AcceptSheet(job: job) { eta in
                let err = await board.accept(job, etaMinutes: eta)
                if let err { actionError = err }
                return err == nil
            }
            .presentationDetents([.height(430)])
        }
        .alert("Could not accept",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    /// The server decides this, not the app. board.verification is the very same
    /// checklist the accept endpoint runs, so the button cannot promise
    /// something the API will refuse a moment later.
    private var canAccept: Bool { board.verification?.ok ?? true }

    private var header: some View {
        HStack {
            Text(board.jobs.isEmpty ? "No jobs nearby"
                                    : "\(board.jobs.count) job\(board.jobs.count == 1 ? "" : "s") nearby")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkDim)
            Spacer()
            if board.isLoading {
                ProgressView().tint(Theme.inkFaint).scaleEffect(0.8)
            }
        }
    }
}

private struct EmptyBoard: View {
    let loading: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkFaint)
            Text(loading ? "Looking for jobs…" : "Nothing here right now")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("New jobs appear the moment a customer requests one.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .cardBackground()
    }
}

/// Why this company cannot take work yet, as a list of steps rather than one
/// blunt refusal. Same wording the dashboard shows, sent by the same endpoint.
private struct VerificationBanner: View {
    let verification: Verification

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(verification.waiting == true ? "Waiting on us" : "Not able to accept jobs yet",
                  systemImage: verification.waiting == true ? "clock" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.amber)

            ForEach(verification.steps ?? []) { step in
                if step.required {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(step.done ? Theme.green : Theme.inkFaint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            if !step.done {
                                Text(step.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            Text("Finish these on the website and they will clear here.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(hex: 0x241D0D))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x7C5A10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Accepting asks for one thing: how long until you are there.
///
/// It is the number the customer watches count down, and the server refuses the
/// job without it. Presets rather than a keyboard — this is tapped one-handed,
/// in a yard, often with gloves on.
struct AcceptSheet: View {
    let job: Job
    /// Returns true when the job was taken, so the sheet knows to close.
    let onAccept: (Int) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var eta = 20
    @State private var working = false

    private let options = [10, 15, 20, 30, 45, 60]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Accept this job")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text("\(job.whereFrom) · \(Money.string(job.net)) to you")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkDim)

                Text("How long until you are there?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.top, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                          spacing: 10) {
                    ForEach(options, id: \.self) { minutes in
                        Button {
                            eta = minutes
                        } label: {
                            // "1 hr", not "60 min" — it is how a dispatcher
                            // says it, and it makes the longest option read as
                            // a real choice rather than the end of a list.
                            Text(minutes == 60 ? "1 hr" : "\(minutes) min")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(eta == minutes ? Theme.accent : Theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(eta == minutes ? Theme.accent.opacity(0.14) : Theme.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(eta == minutes ? Theme.accent : Theme.line,
                                                lineWidth: eta == minutes ? 2 : 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }

                // The consequence, next to the number that causes it. This used
                // to say the customer judges you on it, which was true and
                // toothless — the ETA had no effect on anything. It does now:
                // past it they can walk away and you get nothing, so quoting 10
                // to win a job you cannot reach in 40 costs the whole fee.
                Text("Specify honest ETA times. Your customer is allowed to "
                   + "CANCEL the call after your ETA has passed, and a GOA will "
                   + "not be charged.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.amber.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.amber.opacity(0.30), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer(minLength: 0)

                Button {
                    working = true
                    Task {
                        let ok = await onAccept(eta)
                        working = false
                        if ok { dismiss() }
                        else { dismiss() }   // the board shows the reason
                    }
                } label: {
                    if working {
                        ProgressView().tint(.white)
                    } else {
                        Text("Accept — on scene in \(eta) min")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
            }
            .padding(20)
        }
    }
}
