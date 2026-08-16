import SwiftUI
import UIKit

/// The jobs this company is actually running, and the buttons that move them
/// along. This is the screen a driver has open at the roadside.
struct MyJobsView: View {
    @EnvironmentObject private var board: BoardStore

    @State private var busyJobID: Int?
    @State private var actionError: String?
    @State private var completion: BoardStore.CompletionResult?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if board.myJobs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "truck.box")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.inkFaint)
                            Text("No jobs running")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text("Jobs you accept show up here with the buttons to work them.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.inkFaint)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 46)
                        .cardBackground()
                    } else {
                        ForEach(board.myJobs) { job in
                            LiveJobCard(
                                job: job,
                                busy: busyJobID == job.id,
                                onStatus: { status in advance(job, to: status) },
                                onComplete: { finish(job) }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { await board.refresh() }
        }
        .navigationTitle("My jobs")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could not update",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .alert("Job completed",
               isPresented: Binding(get: { completion != nil },
                                    set: { if !$0 { completion = nil } })) {
            Button("OK", role: .cancel) { completion = nil }
        } message: {
            // The two outcomes are genuinely different and are worded that way.
            // A driver whose customer's card failed has NOT been paid, and being
            // told "completed" with a tick would be the platform's problem
            // dressed up as his success.
            if let c = completion {
                if c.settled {
                    Text("Paid. \(Money.string(c.net ?? 0)) is on its way to your balance.")
                } else {
                    Text("The work is recorded, but the customer's card could not be "
                       + "charged yet. Your payment is pending while we sort it out.")
                }
            }
        }
    }

    private func advance(_ job: Job, to status: String) {
        busyJobID = job.id
        Task {
            let err = await board.setStatus(job, to: status)
            busyJobID = nil
            if let err { actionError = err }
        }
    }

    private func finish(_ job: Job) {
        busyJobID = job.id
        Task {
            let result = await board.complete(job)
            busyJobID = nil
            if result.ok { completion = result }
            else { actionError = result.message }
        }
    }
}

private struct LiveJobCard: View {
    let job: Job
    let busy: Bool
    let onStatus: (String) -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            JobCard(job: job, showAccept: false)

            // Now the job is ours, the customer's details are on it — the
            // server only sends these once the company owns the job.
            if let phone = job.customerPhone, !phone.isEmpty {
                Link(destination: URL(string: "tel:\(phone.filter { $0.isNumber })")!) {
                    Label("Call \(job.customerName ?? "customer") · \(phone)",
                          systemImage: "phone.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .padding(.top, 10)
            }

            if let address = job.pickupAddress, !address.isEmpty {
                Button {
                    openMaps(address)
                } label: {
                    Label(address, systemImage: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 8)
            }

            // One button, whichever one comes next. A row of four with three
            // greyed out is how a driver taps the wrong one in the rain.
            if let next = nextStep {
                Button {
                    if next.status == "completed" { onComplete() } else { onStatus(next.status) }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(next.label) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                .padding(.top, 10)
            }
        }
    }

    private var nextStep: (status: String, label: String)? {
        switch job.status {
        case "awarded":     return (status: "en_route", label: "I am on my way")
        case "en_route":    return (status: "on_scene", label: "I have arrived")
        case "on_scene":
            // A lockout or a jump start finishes on scene; there is no towing
            // step to walk through, and offering one would be a dead end.
            // Written as if/else rather than a ternary — Swift will not always
            // infer a labelled tuple through one.
            if job.serviceType == "tow" {
                return (status: "in_progress", label: "Vehicle loaded")
            } else {
                return (status: "completed", label: "Job complete")
            }
        case "in_progress": return (status: "completed", label: "Job complete")
        default:            return nil
        }
    }

    private func openMaps(_ address: String) {
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Apple Maps is always installed; Google Maps is not.
        if let url = URL(string: "http://maps.apple.com/?daddr=\(q)") {
            UIApplication.shared.open(url)
        }
    }
}
